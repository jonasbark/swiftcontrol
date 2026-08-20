import 'package:bike_control/bluetooth/devices/proxy/proxy_device.dart';
import 'package:bike_control/gen/l10n.dart';
import 'package:bike_control/pages/proxy_device_details/self_test_card.dart';
import 'package:bike_control/services/trainer_self_test/self_test_engine.dart';
import 'package:bike_control/services/trainer_self_test/self_test_result.dart';
import 'package:bike_control/utils/actions/base_actions.dart';
import 'package:bike_control/utils/core.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:universal_ble/universal_ble.dart';

import '../../services/trainer_self_test/fake_self_test_harness.dart';

/// wakelock_plus talks to the host over a pigeon channel that no test binding
/// answers, so every `WakelockPlus.toggle` would reject. Answer it with an
/// empty success reply instead — the card's screen-on handling is not what
/// these tests are about.
const _wakelockChannels = [
  'dev.flutter.pigeon.wakelock_plus_platform_interface.WakelockPlusApi.toggle',
  'dev.flutter.pigeon.wakelock_plus_platform_interface.WakelockPlusApi.isEnabled',
];

void _mockWakelock(bool install) {
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  for (final channel in _wakelockChannels) {
    messenger.setMockMessageHandler(
      channel,
      install ? (_) async => const StandardMessageCodec().encodeMessage(<Object?>[null]) : null,
    );
  }
}

Future<void> main() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  await AppLocalizations.load(const Locale('en'));

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    core.settings.prefs = await SharedPreferences.getInstance();
    core.actionHandler = StubActions();
    _mockWakelock(true);
  });

  tearDown(() => _mockWakelock(false));

  // Connected trainer, no trainer app attached — the state both prechecks pass.
  ProxyDevice connectedTrainer() => ProxyDevice(BleDevice(deviceId: 'x', name: 'KICKR CORE'))..isConnected = true;

  /// One engine tick per `sleep`, but parked behind a zero-duration timer
  /// rather than a bare microtask: `pump()` then leaves the engine mid-run so
  /// the running card can be inspected, and `pumpAndSettle()` drains the whole
  /// test in one go.
  SelfTestEngine engineOver(FakeSelfTestHarness harness) => SelfTestEngine(
    harness: harness,
    sleep: (_) async {
      harness.publishTick();
      await Future<void>.delayed(Duration.zero);
    },
    now: () => DateTime(2026, 8, 20),
  );

  Future<void> pumpCard(
    WidgetTester tester,
    ProxyDevice device,
    FakeSelfTestHarness harness, {
    VoidCallback? onShowOverlaySettings,
  }) async {
    await tester.pumpWidget(
      ShadcnApp(
        localizationsDelegates: const [AppLocalizations.delegate],
        supportedLocales: AppLocalizations.delegate.supportedLocales,
        home: Scaffold(
          child: SelfTestCard(
            device: device,
            engineFactory: () => engineOver(harness),
            onShowOverlaySettings: onShowOverlaySettings,
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('idle card shows start button when trainer connected', (tester) async {
    await pumpCard(tester, connectedTrainer(), FakeSelfTestHarness());

    expect(find.text('Resistance self-test'), findsOneWidget);
    expect(find.text('Test resistance control'), findsOneWidget);
    // Nothing has run yet, so no phase chrome and no stale result.
    expect(find.text('Stop test'), findsNothing);
    expect(find.textContaining('Last test:'), findsNothing);
  });

  testWidgets('refuses while the trainer app is connected', (tester) async {
    final device = connectedTrainer()..debugSetTrainerAppConnected(true);

    await pumpCard(tester, device, FakeSelfTestHarness());
    await tester.tap(find.text('Test resistance control'));
    await tester.pump();

    expect(find.textContaining('exclusive control'), findsOneWidget);
    // Refusal only — the test must not have started behind the message.
    expect(find.text('Stop test'), findsNothing);
    expect(find.text('Test resistance control'), findsOneWidget);
  });

  testWidgets('refuses while the trainer is disconnected', (tester) async {
    final device = ProxyDevice(BleDevice(deviceId: 'x', name: 'KICKR CORE'));

    await pumpCard(tester, device, FakeSelfTestHarness());
    await tester.tap(find.text('Test resistance control'));
    await tester.pump();

    expect(find.text('Connect your trainer first to run the test.'), findsOneWidget);
    expect(find.text('Stop test'), findsNothing);
  });

  testWidgets('running test shows phase progress and stop button, then a verdict', (tester) async {
    final harness = FakeSelfTestHarness();

    await pumpCard(tester, connectedTrainer(), harness);
    await tester.tap(find.text('Test resistance control'));
    await tester.pump();

    // Mid-run: guidance + a way out, and the start button is gone.
    expect(find.text('Measuring baseline'), findsOneWidget);
    expect(find.text('Pedal at a steady, comfortable pace.'), findsOneWidget);
    expect(find.text('Stop test'), findsOneWidget);
    expect(find.text('Test resistance control'), findsNothing);

    await tester.pumpAndSettle();

    // Obedient trainer → PASS.
    expect(find.text('Your trainer responds correctly'), findsOneWidget);
    expect(find.text('Run again'), findsOneWidget);
    expect(find.text('Stop test'), findsNothing);
    // A non-aborted verdict is persisted per trainer for the support bundle.
    expect(core.settings.getSelfTestResultJson('KICKR CORE'), isNotNull);
  });

  testWidgets('Run again starts a second run on a fresh engine', (tester) async {
    final harness = FakeSelfTestHarness();

    await pumpCard(tester, connectedTrainer(), harness);
    await tester.tap(find.text('Test resistance control'));
    await tester.pumpAndSettle();
    expect(find.text('Run again'), findsOneWidget);

    await tester.tap(find.text('Run again'));
    await tester.pump();

    // SelfTestEngine.run is single-shot: a reused engine would hand back the
    // finished result instead of measuring again, so the card would jump
    // straight back to the verdict rather than showing a run in progress.
    expect(find.text('Stop test'), findsOneWidget);
    expect(find.text('Run again'), findsNothing);

    await tester.pumpAndSettle();
    expect(find.text('Your trainer responds correctly'), findsOneWidget);
  });

  testWidgets('PASS verdict offers the overlay CTA and fires the callback', (tester) async {
    var revealed = false;

    await pumpCard(
      tester,
      connectedTrainer(),
      FakeSelfTestHarness(),
      onShowOverlaySettings: () => revealed = true,
    );
    await tester.tap(find.text('Test resistance control'));
    await tester.pumpAndSettle();

    expect(find.text('Your trainer responds correctly'), findsOneWidget);
    expect(find.text('Show gear overlay setup'), findsOneWidget);

    await tester.tap(find.text('Show gear overlay setup'));

    expect(revealed, isTrue);
  });

  testWidgets('ergOkVsFail offers mode switch that flips the fake and reruns', (tester) async {
    final harness = FakeSelfTestHarness()..obeysShift = false;

    await pumpCard(tester, connectedTrainer(), harness);
    await tester.tap(find.text('Test resistance control'));
    await tester.pumpAndSettle();

    expect(find.text("Power targets work, shifting doesn't"), findsOneWidget);
    expect(find.text('Switch mode & run again'), findsOneWidget);
    // Also offered on this verdict — a rider who'd rather just report it.
    expect(find.text('Send result to support'), findsOneWidget);
    expect(harness.vsModeName, 'targetPower');

    await tester.tap(find.text('Switch mode & run again'));
    await tester.pump();

    // The switch flips the fake's recorded mode before the fresh run starts.
    expect(harness.vsModeName, 'trackResistance');
    expect(find.text('Stop test'), findsOneWidget);

    await tester.pumpAndSettle();
    // obeysShift is still false, so the rerun lands on the same verdict.
    expect(find.text("Power targets work, shifting doesn't"), findsOneWidget);
  });

  testWidgets('noControl offers the support CTA', (tester) async {
    final harness = FakeSelfTestHarness()
      ..obeysErg = false
      ..obeysShift = false;

    await pumpCard(tester, connectedTrainer(), harness);
    await tester.tap(find.text('Test resistance control'));
    await tester.pumpAndSettle();

    expect(find.text("Trainer isn't responding to BikeControl"), findsOneWidget);
    expect(find.text('Send result to support'), findsOneWidget);
    // NO_CONTROL has no mode-switch CTA — the ERG phase failed too.
    expect(find.text('Switch mode & run again'), findsNothing);
  });

  testWidgets('last-result chip renders when a stored result exists', (tester) async {
    final stored = SelfTestResult(
      at: DateTime(2026, 8, 19),
      verdict: SelfTestVerdict.pass,
      ergStepsPassed: 3,
      ergStepsTotal: 3,
      shiftStepsPassed: 2,
      shiftStepsTotal: 3,
      vsMode: 'targetPower',
      protocol: 'ftms',
    );
    await core.settings.setSelfTestResultJson('KICKR CORE', stored.toJsonString());

    await pumpCard(tester, connectedTrainer(), FakeSelfTestHarness());

    expect(find.textContaining('Last test:'), findsOneWidget);
    expect(find.text('Test resistance control'), findsOneWidget);
  });

  testWidgets('keep-pedaling banner shows when pausedForCadence', (tester) async {
    final harness = FakeSelfTestHarness()..riderCadence = 0;
    final engine = SelfTestEngine(
      harness: harness,
      sleep: (d) async {
        harness.publishTick();
        await Future<void>.delayed(d);
      },
      now: () => DateTime(2026, 8, 20),
    );

    await tester.pumpWidget(
      ShadcnApp(
        localizationsDelegates: const [AppLocalizations.delegate],
        supportedLocales: AppLocalizations.delegate.supportedLocales,
        home: Scaffold(
          child: SelfTestCard(device: connectedTrainer(), engineFactory: () => engine),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('Test resistance control'));
    await tester.pump();

    // Cadence stuck at 0 rpm throughout: precheck passes immediately (power
    // still flows), then baseline's pause watchdog arms and, after the 4s
    // low-cadence threshold, pauses — well short of the 20s timeout that
    // would abort the run.
    for (var i = 0; i < 15; i++) {
      await tester.pump(SelfTestEngine.tick);
    }

    expect(find.text('Keep pedaling to continue the test'), findsOneWidget);
    expect(find.text('Stop test'), findsOneWidget);

    // Drain the engine's own pending tick before the test ends — cancel()
    // only flags intent; the tick already in flight has to actually fire
    // (pumpAndSettle alone won't advance far enough to reach it on its own)
    // before the abort can cascade through, or the un-awaited Timer left
    // running past teardown fails the test binding's own invariant check.
    engine.cancel();
    await tester.pump(SelfTestEngine.tick);
    await tester.pumpAndSettle();
  });

  testWidgets('cancel produces an aborted verdict that is not persisted', (tester) async {
    final harness = FakeSelfTestHarness();

    await pumpCard(tester, connectedTrainer(), harness);
    await tester.tap(find.text('Test resistance control'));
    await tester.pump();
    expect(find.text('Stop test'), findsOneWidget);

    await tester.tap(find.text('Stop test'));
    await tester.pump();

    // Disabled while the aborted verdict is still in flight — a second tap
    // must not race the engine's own cancel → restore → finish sequence.
    expect(tester.widget<Button>(find.widgetWithText(Button, 'Stop test')).onPressed, isNull);

    await tester.pumpAndSettle();

    expect(find.text('Test stopped'), findsOneWidget);
    // Aborted runs measured nothing worth keeping.
    expect(core.settings.getSelfTestResultJson('KICKR CORE'), isNull);
  });
}
