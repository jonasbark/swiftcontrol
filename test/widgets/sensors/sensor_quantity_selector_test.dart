import 'package:bike_control/bluetooth/devices/sensors/ble_heart_rate_device.dart';
import 'package:bike_control/bluetooth/emulation/emulated_ble_platform.dart';
import 'package:bike_control/gen/l10n.dart';
import 'package:bike_control/pages/sensors/sensors_section.dart';
import 'package:bike_control/services/sensors/ble_sensor_source.dart';
import 'package:bike_control/services/sensors/fake_sensor_source.dart';
import 'package:bike_control/services/sensors/sensor_quantity.dart';
import 'package:bike_control/utils/actions/base_actions.dart';
import 'package:bike_control/utils/core.dart';
import 'package:bike_control/utils/iap/iap_manager.dart';
import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:flutter_local_notifications_platform_interface/flutter_local_notifications_platform_interface.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:universal_ble/universal_ble.dart';

/// No-op local-notifications backend — the real connect path
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

/// Sensor-sources-phase2 UI redesign: `SensorQuantitySelector`'s toggle group
/// lists nearby, not-yet-connected sensors alongside connected ones (task A),
/// and selecting a not-yet-connected one drives a REAL connect through
/// `Connection` (task B) — the same end-to-end reachability story
/// `sensor_discovery_section_test.dart` proved for the deleted Connect
/// button, now proved for the toggle group that replaced it.
///
/// Mounts the REAL global hub (`core.sensors`), not a fresh `SensorHub()`:
/// `Connection._registerSensorSource` always registers into `core.sensors`
/// specifically, so a test that wants a real connect to show up in the UI
/// has to watch the same hub production code writes to. Each test that
/// touches it cleans up via `addTearDown` so later tests in this file start
/// from a clean selection/registration for the ids they care about.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // The page's Pro badge reaches IAPManager, which reaches Supabase.instance;
  // give it an offline dummy instance (no session, so no request is made).
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'http://127.0.0.1:9',
      anonKey: 'sensor-quantity-selector-test-anon-key',
      debug: false,
      authOptions: const FlutterAuthClientOptions(
        localStorage: EmptyLocalStorage(),
        detectSessionInUri: false,
        autoRefreshToken: false,
      ),
    );
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    core.settings.prefs = await SharedPreferences.getInstance();
    core.actionHandler = StubActions();
    core.connection.devices.clear();
    FlutterLocalNotificationsPlatform.instance = _FakeLocalNotificationsPlatform();
    IAPManager.instance.setProForTesting(enabled: false);
  });

  tearDown(() {
    core.connection.devices.clear();
    IAPManager.instance.setProForTesting(enabled: false);
  });

  FakePeripheral strapPeripheral({required String deviceId, String name = 'TICKR 1234'}) => FakePeripheral(
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
        home: Scaffold(child: SensorsSection(hub: core.sensors)),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('lists a nearby, not-yet-connected sensor with its kind and not-connected state', (tester) async {
    final device = BleHeartRateDevice(BleDevice(deviceId: 'hr-toggle-1', name: 'TICKR 1234'));
    core.connection.devices.add(device);

    await pump(tester);

    expect(find.byKey(const Key('sensor-toggle-heartRate-hr-toggle-1')), findsOneWidget);
    expect(find.text('TICKR 1234'), findsOneWidget);
    expect(find.text(AppLocalizations.current.sensorKindHeartRateMonitor), findsOneWidget);
    expect(find.text(AppLocalizations.current.notConnected), findsOneWidget);
  });

  testWidgets('a registered (connected) source is not offered as "not connected", and shows its live reading',
      (tester) async {
    final source = FakeSensorSource(id: 'hr-toggle-2', displayName: 'TICKR 5678', provides: {
      SensorQuantity.heartRate,
    });
    core.sensors.register(source);
    source.emit(SensorQuantity.heartRate, 150);
    addTearDown(() {
      core.sensors.unregister(source.id);
      core.sensors.select(SensorQuantity.heartRate, null);
    });

    await pump(tester);

    expect(find.byKey(const Key('sensor-toggle-heartRate-hr-toggle-2')), findsOneWidget);
    expect(find.text(AppLocalizations.current.notConnected), findsNothing);
    expect(find.text(AppLocalizations.current.sensorValueHeartRate(150)), findsOneWidget);
  });

  testWidgets('selecting nothing leaves the trainer selected by default for every row', (tester) async {
    await pump(tester);

    expect(find.byKey(const Key('sensor-toggle-heartRate-trainer')), findsOneWidget);
    expect(find.byKey(const Key('sensor-toggle-cadence-trainer')), findsOneWidget);
    expect(find.byKey(const Key('sensor-toggle-power-trainer')), findsOneWidget);
    expect(core.sensors.selectionFor(SensorQuantity.heartRate), isNull);
    expect(core.sensors.selectionFor(SensorQuantity.cadence), isNull);
    expect(core.sensors.selectionFor(SensorQuantity.power), isNull);
  });

  group('selection triggers connection', () {
    testWidgets('persists consent before connecting, then drives the device to a real connected state',
        (tester) async {
      IAPManager.instance.setProForTesting(enabled: true);
      final ble = FakeUniversalBlePlatform();
      UniversalBle.setInstance(ble);
      final peripheral = strapPeripheral(deviceId: 'hr-toggle-3');
      ble.addPeripheral(peripheral);
      final device = BleHeartRateDevice(peripheral.scanResult);
      core.connection.devices.add(device);
      addTearDown(() {
        core.sensors.unregister(device.source.id);
        core.sensors.select(SensorQuantity.heartRate, null);
      });
      expect(device.shouldAutoConnect, isFalse);

      await pump(tester);
      await tester.tap(find.byKey(const Key('sensor-toggle-heartRate-hr-toggle-3')));
      await tester.pumpAndSettle();

      expect(device.isConnected, isTrue);
      // Persisted, not just in-memory (see `Settings.getSensorAutoConnect`'s
      // doc comment) — AND proof of the load-bearing ordering: had the flag
      // been written after calling connect() instead of before,
      // `shouldAutoConnect` would have read false at connect() time,
      // `connect()` would have early-returned, and `isConnected` above would
      // still be false no matter what the flag reads now.
      expect(core.settings.getSensorAutoConnect(device.device.deviceId), isTrue);
      expect(core.sensors.selectionFor(SensorQuantity.heartRate), device.source.id);
    });

    // Deliberately no automated widget test drives a FAILED connect through
    // the real `Connection`/`FakeUniversalBlePlatform` stack here. Spiking
    // one during this task surfaced a pre-existing infrastructure gap: under
    // `testWidgets`' FakeAsync zone, `Connection._connect`'s catch block
    // (specifically awaiting the cancellation of the action-stream
    // subscription it sets up before calling `device.connect()`) does not
    // resolve within any bounded number of `pump()`/`pumpAndSettle()` calls
    // once `device.connect()` has actually rejected — reproduced with plain
    // `BluetoothDevice`/`Connection` primitives, nothing sensor-specific,
    // and independent of which error `device.connect()` rejects with. No
    // existing test in this codebase drives a failing connect through
    // `Connection` from a `testWidgets` context (`sensor_discovery_section
    // _test.dart`'s deleted "tapping Connect" test only ever covered the
    // success path), so this is not a regression. `_SensorToggle`'s failure
    // rendering (the `_failed` flag driving the icon/text branch in its
    // `renderChild` callback) is instead verified by code review: it is
    // gated on `LoadingWidget.onErrorCallback`, the exact same,
    // already-shipped mechanism the deleted `SensorDiscoverySection`'s
    // Connect button relied on for its own (also untested) failure path,
    // and `SensorQuantitySelector._select`'s catch block forwards through
    // `recordError` before rethrowing so `LoadingWidget` still sees the
    // failure regardless.
  });
}
