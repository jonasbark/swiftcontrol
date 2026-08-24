// Task 9: the personalized "Your setup" section. Pins: the network
// troubleshooting row only appears while a network trainer connection is
// started/connected; the Zwift Click V2 setup-options row only appears while
// a Click V2 side (left or right) is among the known devices; and an empty
// setup shows a muted nudge toward onboarding instead of an empty card. Both
// rows push their target page via `context.push`.
import 'package:bike_control/bluetooth/devices/base_device.dart';
import 'package:bike_control/bluetooth/devices/trainer_connection.dart';
import 'package:bike_control/bluetooth/devices/zwift/zwift_clickv2.dart';
import 'package:bike_control/bluetooth/devices/zwift/zwift_clickv2_right_side.dart';
import 'package:bike_control/gen/l10n.dart';
import 'package:bike_control/pages/click_v2_onboarding.dart';
import 'package:bike_control/pages/help_center/widgets/your_setup_section.dart';
import 'package:bike_control/pages/network_troubleshooting_page.dart';
import 'package:bike_control/utils/actions/base_actions.dart';
import 'package:bike_control/utils/core.dart';
import 'package:bike_control/utils/keymap/keymap.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:universal_ble/universal_ble.dart';

const _networkRowKey = ValueKey('help-network-troubleshoot');
const _clickV2RowKey = ValueKey('help-clickv2-onboarding');

class _FakeConnection extends TrainerConnection {
  _FakeConnection({required super.type}) : super(title: () => 'Fake connection', supportedActions: const []);

  @override
  Future<ActionResult> sendAction(KeyPair keyPair, {required bool isKeyDown, required bool isKeyUp}) async =>
      NotHandled('', button: null);

  @override
  Widget getTile({bool small = false}) => const SizedBox.shrink();
}

Future<void> _pump(
  WidgetTester tester, {
  List<BaseDevice>? devices,
  List<TrainerConnection>? connections,
}) {
  return tester.pumpWidget(
    ShadcnApp(
      debugShowCheckedModeBanner: false,
      localizationsDelegates: const [AppLocalizations.delegate],
      supportedLocales: AppLocalizations.delegate.supportedLocales,
      home: Scaffold(
        child: YourSetupSection(devicesOverride: devices, connectionsOverride: connections),
      ),
    ),
  );
}

Future<void> main() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  final l10n = await AppLocalizations.load(const Locale('en'));

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    core.settings.prefs = await SharedPreferences.getInstance();
    core.actionHandler = StubActions();
  });

  group('network troubleshooting row', () {
    testWidgets('shown when a network connection is started', (tester) async {
      final connection = _FakeConnection(type: ConnectionMethodType.network)..isStarted.value = true;

      await _pump(tester, devices: const [], connections: [connection]);
      await tester.pump();

      expect(find.byKey(_networkRowKey), findsOneWidget);
    });

    testWidgets('shown when a network connection is connected', (tester) async {
      final connection = _FakeConnection(type: ConnectionMethodType.network)..isConnected.value = true;

      await _pump(tester, devices: const [], connections: [connection]);
      await tester.pump();

      expect(find.byKey(_networkRowKey), findsOneWidget);
    });

    testWidgets('absent without any started/connected network connection', (tester) async {
      final idleNetwork = _FakeConnection(type: ConnectionMethodType.network);
      final startedBluetooth = _FakeConnection(type: ConnectionMethodType.bluetooth)..isStarted.value = true;

      await _pump(tester, devices: const [], connections: [idleNetwork, startedBluetooth]);
      await tester.pump();

      expect(find.byKey(_networkRowKey), findsNothing);
    });

    testWidgets('tapping it pushes NetworkTroubleshootingPage', (tester) async {
      final connection = _FakeConnection(type: ConnectionMethodType.network)..isStarted.value = true;

      await _pump(tester, devices: const [], connections: [connection]);
      await tester.pump();

      // Not pumpAndSettle: NetworkTroubleshootingPage kicks off a self-test
      // engine with its own timers/polling, which never settles.
      await tester.tap(find.byKey(_networkRowKey));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(tester.takeException(), isNull);
      expect(find.byType(NetworkTroubleshootingPage), findsOneWidget);
    });
  });

  group('Zwift Click V2 row', () {
    testWidgets('shown when a Click V2 right side is a known device', (tester) async {
      final rightSide = ZwiftClickV2RightSide(BleDevice(deviceId: 'r1', name: 'Zwift Click'));

      await _pump(tester, devices: [rightSide], connections: const []);
      await tester.pump();

      expect(find.byKey(_clickV2RowKey), findsOneWidget);
    });

    testWidgets('shown when a unified Click V2 is a known device', (tester) async {
      final unified = ZwiftClickV2(BleDevice(deviceId: 'l1', name: 'Zwift Click'));

      await _pump(tester, devices: [unified], connections: const []);
      await tester.pump();

      expect(find.byKey(_clickV2RowKey), findsOneWidget);
    });

    testWidgets('absent without any Click V2 device', (tester) async {
      await _pump(tester, devices: const [], connections: const []);
      await tester.pump();

      expect(find.byKey(_clickV2RowKey), findsNothing);
    });

    testWidgets('tapping it pushes ClickV2OnboardingPage', (tester) async {
      final rightSide = ZwiftClickV2RightSide(BleDevice(deviceId: 'r1', name: 'Zwift Click'));

      await _pump(tester, devices: [rightSide], connections: const []);
      await tester.pump();

      // Not pumpAndSettle: ClickV2OnboardingPage's rows animate in via a
      // one-shot AnimationController, but held here mid-transition is enough
      // to confirm the push happened.
      await tester.tap(find.byKey(_clickV2RowKey));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(tester.takeException(), isNull);
      expect(find.byType(ClickV2OnboardingPage), findsOneWidget);
    });
  });

  group('empty state', () {
    testWidgets('shows a muted nudge toward the setup wizard when nothing is configured', (tester) async {
      await _pump(tester, devices: const [], connections: const []);
      await tester.pump();

      expect(find.text(l10n.helpCenterNoSetup), findsOneWidget);
      expect(find.byKey(_networkRowKey), findsNothing);
      expect(find.byKey(_clickV2RowKey), findsNothing);
    });
  });
}
