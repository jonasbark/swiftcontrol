import 'package:bike_control/bluetooth/devices/proxy/proxy_device.dart';
import 'package:bike_control/gen/l10n.dart';
import 'package:bike_control/pages/proxy_device_details/self_test_card.dart';
import 'package:bike_control/services/trainer_self_test/self_test_engine.dart';
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

  Future<void> pumpCard(WidgetTester tester, ProxyDevice device, FakeSelfTestHarness harness) async {
    await tester.pumpWidget(
      ShadcnApp(
        localizationsDelegates: const [AppLocalizations.delegate],
        supportedLocales: AppLocalizations.delegate.supportedLocales,
        home: Scaffold(
          child: SelfTestCard(device: device, engineFactory: () => engineOver(harness)),
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

    // Obedient trainer → PASS, and this task renders title + rerun only.
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
}
