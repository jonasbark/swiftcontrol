import 'package:bike_control/bluetooth/devices/sensors/ble_cadence_device.dart';
import 'package:bike_control/bluetooth/devices/sensors/ble_heart_rate_device.dart';
import 'package:bike_control/bluetooth/emulation/emulated_ble_platform.dart';
import 'package:bike_control/gen/l10n.dart';
import 'package:bike_control/pages/sensors/sensor_discovery_section.dart';
import 'package:bike_control/services/sensors/ble_sensor_source.dart';
import 'package:bike_control/utils/actions/base_actions.dart';
import 'package:bike_control/utils/core.dart';
import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:flutter_local_notifications_platform_interface/flutter_local_notifications_platform_interface.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:universal_ble/universal_ble.dart';

/// No-op local-notifications backend — the real production connect path
/// (`Connection._connect`) posts a "connected" notification on success, and
/// the plugin's static platform instance is only set by real plugin
/// registration. Mirrors `test/integration/harness/test_env.dart`'s own fake.
class _FakeLocalNotificationsPlatform extends FlutterLocalNotificationsPlatform {
  @override
  Future<void> show({required int id, String? title, String? body, String? payload}) async {}

  @override
  Future<void> cancel({required int id}) async {}

  @override
  Future<void> cancelAll() async {}
}

/// V1b (wave 3): the other half of `SensorsSection`'s reachability story. A
/// heart rate strap the scanner has discovered but never connected has no
/// path to ever become connectable without this — `shouldAutoConnect` is
/// deliberately false until the rider explicitly asks (fix-wave-1, F1), and
/// `SensorsSection`'s own paired-sources list only ever shows a strap that is
/// ALREADY connected (`SensorHub.register` fires from `Connection`'s
/// post-connect hook, never before). This widget is the rider action that
/// closes that gap; without it, a mounted `SensorsSection` could list a
/// source only if something else outside the app's UI had connected it.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    core.settings.prefs = await SharedPreferences.getInstance();
    core.actionHandler = StubActions();
    core.connection.devices.clear();
    FlutterLocalNotificationsPlatform.instance = _FakeLocalNotificationsPlatform();
  });

  tearDown(() => core.connection.devices.clear());

  FakePeripheral strapPeripheral({String deviceId = 'hr-1', String name = 'TICKR 1234'}) => FakePeripheral(
    deviceId: deviceId,
    name: name,
    advertisedServices: [BleSensorSource.heartRateServiceUuid],
    services: [
      BleService(BleSensorSource.heartRateServiceUuid, [
        BleCharacteristic(BleSensorSource.heartRateMeasurementUuid, [CharacteristicProperty.notify], const []),
      ]),
    ],
  );

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      ShadcnApp(
        localizationsDelegates: [
          ...ShadcnLocalizations.localizationsDelegates,
          AppLocalizations.delegate,
        ],
        supportedLocales: const [Locale('en')],
        home: const Scaffold(child: SensorDiscoverySection()),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('lists a discovered, not-yet-connected strap with a Connect action', (tester) async {
    final device = BleHeartRateDevice(BleDevice(deviceId: 'hr-1', name: 'TICKR 1234'));
    core.connection.devices.add(device);

    await pump(tester);

    expect(find.text('TICKR 1234'), findsOneWidget);
    expect(find.text(AppLocalizations.current.connect), findsOneWidget);
  });

  // A1 (fix-wave-A): before widening this section's dispatch from the
  // concrete `BleHeartRateDevice` to the shared `BleSensorDevice` interface,
  // a discovered cadence sensor or power meter never appeared here at all —
  // there was no route to a Connect action, so it could never reach
  // connected state, so its source could never reach the hub. This proves
  // the widget itself, not just `Connection`, now treats a cadence sensor
  // the same way as a strap.
  testWidgets('lists a discovered, not-yet-connected cadence sensor with a Connect action too', (tester) async {
    final device = BleCadenceDevice(BleDevice(deviceId: 'csc-1', name: 'CAD 7788'));
    core.connection.devices.add(device);

    await pump(tester);

    expect(find.text('CAD 7788'), findsOneWidget);
    expect(find.text(AppLocalizations.current.connect), findsOneWidget);
  });

  testWidgets('renders nothing when there is nothing nearby to connect', (tester) async {
    await pump(tester);

    expect(find.byType(SensorDiscoverySection), findsOneWidget);
    expect(find.text(AppLocalizations.current.connect), findsNothing);
  });

  testWidgets('an already-connected strap is not offered again', (tester) async {
    final device = BleHeartRateDevice(BleDevice(deviceId: 'hr-1', name: 'TICKR 1234'))..isConnected = true;
    core.connection.devices.add(device);

    await pump(tester);

    expect(find.text(AppLocalizations.current.connect), findsNothing);
  });

  // The actual reachability proof this whole fix exists for: a strap
  // discovered by the scanner, with no other production path to ever become
  // connectable, reaches a real connected state through nothing but a rider
  // tapping Connect — driven through `Connection.connectDevice`, the exact
  // production entry point, against a fake BLE platform standing in for the
  // radio.
  testWidgets('tapping Connect drives the device to a real connected state', (tester) async {
    final ble = FakeUniversalBlePlatform();
    UniversalBle.setInstance(ble);
    final peripheral = strapPeripheral();
    ble.addPeripheral(peripheral);
    final device = BleHeartRateDevice(peripheral.scanResult);
    core.connection.devices.add(device);
    expect(device.shouldAutoConnect, isFalse);

    await pump(tester);
    await tester.tap(find.text(AppLocalizations.current.connect));
    await tester.pumpAndSettle();

    expect(device.isConnected, isTrue);
    // Persisted, not just in-memory: the strap must reconnect on its own the
    // next time it is rediscovered, exactly like every other remembered
    // device — see `Settings.getSensorAutoConnect`'s doc comment.
    expect(core.settings.getSensorAutoConnect(device.device.deviceId), isTrue);
    // Reflects the new state without the rider leaving and reopening the
    // page: now connected, it drops off the "nearby" list.
    expect(find.text(AppLocalizations.current.connect), findsNothing);
  });
}
