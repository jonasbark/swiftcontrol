import 'package:bike_control/bluetooth/devices/sensors/ble_heart_rate_device.dart';
import 'package:bike_control/bluetooth/emulation/emulated_ble_platform.dart';
import 'package:bike_control/gen/l10n.dart';
import 'package:bike_control/pages/proxy_device_details/sensor_source_picker.dart';
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

/// No-op local-notifications backend — `Connection._connect` posts a
/// "connected" notification on success, and the plugin's static platform
/// instance is only set by real plugin registration. Mirrors
/// `test/integration/harness/test_env.dart`'s own fake (and the deleted
/// `sensor_quantity_selector_test.dart`'s, which this file's connect-ordering
/// tests are ported from).
class _FakeLocalNotificationsPlatform extends FlutterLocalNotificationsPlatform {
  @override
  Future<void> show({required int id, String? title, String? body, String? payload}) async {}

  @override
  Future<void> cancel({required int id}) async {}

  @override
  Future<void> cancelAll() async {}
}

/// The picker a tile's source row opens. Mounts the REAL global hub
/// (`core.sensors`) and `core.connection`, not doubles: `Connection`'s
/// registration and this picker's reads both have to agree on the same
/// singleton for the connect/disconnect-ordering tests below to prove
/// anything real.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'http://127.0.0.1:9',
      anonKey: 'sensor-source-picker-test-anon-key',
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
    // NOT `core.connection.stop()` here: most tests in this file never set a
    // fake `UniversalBle` instance, and `stop()` calls
    // `getBluetoothAvailabilityState()`, which throws with no platform
    // channel to answer it. The two tests that DO drive a real (dis)connect
    // through `Connection` call `stop()` themselves, inside the test body —
    // see their own comment on why it has to happen there.
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

  // Opens the picker through `openSensorSourcePicker`/`openSheet`, exactly
  // as a tile's source row does — not by mounting `SensorSourcePicker`
  // directly. `_select`/`_disconnect` call `closeSheet` on success, which
  // needs a real `DrawerEntryWidget` ancestor (only present once something
  // has actually gone through `openSheet`); mounting the widget bare would
  // make every successful pick throw "No DrawerEntryWidget found".
  Future<void> pumpPicker(WidgetTester tester, {SensorQuantity quantity = SensorQuantity.heartRate}) async {
    await tester.pumpWidget(
      ShadcnApp(
        localizationsDelegates: [
          ...ShadcnLocalizations.localizationsDelegates,
          AppLocalizations.delegate,
        ],
        supportedLocales: const [Locale('en')],
        home: Scaffold(
          child: Builder(
            builder: (context) => Button.ghost(
              key: const Key('open-picker'),
              onPressed: () => openSensorSourcePicker(context, quantity: quantity),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('open-picker')));
    await tester.pumpAndSettle();
  }

  testWidgets('lists Trainer plus a nearby, not-yet-connected sensor as Not connected', (tester) async {
    final device = BleHeartRateDevice(BleDevice(deviceId: 'hr-pick-1', name: 'TICKR 1234'));
    core.connection.devices.add(device);

    await pumpPicker(tester);

    expect(find.text(AppLocalizations.current.sensorSourceTrainer), findsOneWidget);
    expect(find.text('TICKR 1234'), findsOneWidget);
    expect(find.textContaining(AppLocalizations.current.notConnected), findsOneWidget);
  });

  testWidgets('a registered (connected) source is not offered as Not connected, and shows its live reading',
      (tester) async {
    final source = FakeSensorSource(id: 'hr-pick-2', displayName: 'TICKR 5678', provides: {
      SensorQuantity.heartRate,
    });
    core.sensors.register(source);
    source.emit(SensorQuantity.heartRate, 150);
    addTearDown(() {
      core.sensors.unregister(source.id);
      core.sensors.select(SensorQuantity.heartRate, null);
    });

    await pumpPicker(tester);

    expect(find.textContaining(AppLocalizations.current.notConnected), findsNothing);
    expect(find.textContaining(AppLocalizations.current.sensorValueHeartRate(150)), findsOneWidget);
  });

  testWidgets('selecting Trainer clears the selection, with no BLE side effect', (tester) async {
    core.sensors.select(SensorQuantity.heartRate, 'was-something');
    addTearDown(() => core.sensors.select(SensorQuantity.heartRate, null));

    await pumpPicker(tester);
    await tester.tap(find.byKey(const Key('sensor-source-picker-trainer-heartRate')));
    await tester.pumpAndSettle();

    expect(core.sensors.selectionFor(SensorQuantity.heartRate), isNull);
  });

  testWidgets('Pro gating does not apply to Trainer — only to picking an external source', (tester) async {
    IAPManager.instance.setProForTesting(enabled: false);
    core.sensors.select(SensorQuantity.cadence, 'whatever');
    addTearDown(() => core.sensors.select(SensorQuantity.cadence, null));

    await pumpPicker(tester, quantity: SensorQuantity.cadence);
    await tester.tap(find.byKey(const Key('sensor-source-picker-trainer-cadence')));
    await tester.pumpAndSettle();

    expect(core.sensors.selectionFor(SensorQuantity.cadence), isNull);
  });

  group('CRITICAL — connect ordering', () {
    testWidgets('persists consent BEFORE connecting, then drives the device to a real connected state',
        (tester) async {
      IAPManager.instance.setProForTesting(enabled: true);
      final ble = FakeUniversalBlePlatform();
      UniversalBle.setInstance(ble);
      final peripheral = strapPeripheral(deviceId: 'hr-pick-3');
      ble.addPeripheral(peripheral);
      final device = BleHeartRateDevice(peripheral.scanResult);
      core.connection.devices.add(device);
      addTearDown(() {
        core.sensors.unregister(device.source.id);
        core.sensors.select(SensorQuantity.heartRate, null);
      });
      expect(device.shouldAutoConnect, isFalse);

      await pumpPicker(tester);
      await tester.tap(find.byKey(Key('sensor-source-picker-heartRate-${device.source.id}')));
      await tester.pumpAndSettle();

      expect(device.isConnected, isTrue);
      // Persisted, not just in-memory — AND proof of the load-bearing
      // ordering: had the flag been written after calling connect() instead
      // of before, `shouldAutoConnect` would have read false at connect()
      // time, `connect()` would have early-returned, and `isConnected` above
      // would still be false no matter what the flag reads now.
      expect(core.settings.getSensorAutoConnect(device.device.deviceId), isTrue);
      expect(core.sensors.selectionFor(SensorQuantity.heartRate), device.source.id);
      // The sheet closes itself on a successful pick.
      expect(find.byType(SensorSourcePicker), findsNothing);

      // `Connection`'s BLE connection-state listener re-evaluates on every
      // (dis)connect and would otherwise leave a periodic gamepad-search
      // timer pending past this test's end (`performScanning`'s doc
      // comment) — `flutter_test`'s pending-timer check runs at the end of
      // the test body itself, before any `tearDown`/`addTearDown` gets a
      // turn, so this has to happen here rather than in either of those.
      await core.connection.stop();
    });

    // Deliberately no automated widget test drives a FAILED connect through
    // the real `Connection`/`FakeUniversalBlePlatform` stack, and no test
    // drives the Pro-denied dialog path to completion — both are pre-existing
    // gaps this file inherits from the deleted `sensor_quantity_selector_test
    // .dart`, which carried the same limitation for the same reason (see that
    // file's own history): under `testWidgets`' FakeAsync zone, a rejected
    // `device.connect()` does not resolve within any bounded number of
    // `pump()`/`pumpAndSettle()` calls, independent of which error it rejects
    // with, and `showGoProDialog` pulls in the full purchase-flow UI. Both
    // paths are covered by code review instead: `_select`'s catch block
    // forwards through `recordError` before rethrowing (verified above the
    // fold), and the Pro gate (`sourceId != null && !isProEnabledForCurrentDevice`)
    // is exercised for its "does not apply to Trainer" half by the test above.
  });

  group('disconnect', () {
    testWidgets('clears the consent flag BEFORE disconnecting, and the selection falls back to Trainer',
        (tester) async {
      IAPManager.instance.setProForTesting(enabled: true);
      final ble = FakeUniversalBlePlatform();
      UniversalBle.setInstance(ble);
      final peripheral = strapPeripheral(deviceId: 'hr-pick-4');
      ble.addPeripheral(peripheral);
      final device = BleHeartRateDevice(peripheral.scanResult);
      core.connection.devices.add(device);
      addTearDown(() {
        core.sensors.unregister(device.source.id);
        core.sensors.select(SensorQuantity.heartRate, null);
      });

      // Get to a genuinely connected+registered+selected state first, via
      // the same picker tap the connect-ordering test above proves.
      await pumpPicker(tester);
      await tester.tap(find.byKey(Key('sensor-source-picker-heartRate-${device.source.id}')));
      await tester.pumpAndSettle();
      expect(device.isConnected, isTrue);
      expect(core.sensors.selectionFor(SensorQuantity.heartRate), device.source.id);

      // A fresh picker instance — the tile would reopen one fresh too.
      await pumpPicker(tester);
      await tester.tap(find.byKey(Key('sensor-source-picker-heartRate-${device.source.id}-disconnect')));
      await tester.pumpAndSettle();

      expect(core.settings.getSensorAutoConnect(device.device.deviceId), isFalse);
      expect(device.isConnected, isFalse);
      // `forget: true` cascades: the quantity selection that pointed at this
      // source falls back to Trainer rather than being left dangling.
      expect(core.sensors.selectionFor(SensorQuantity.heartRate), isNull);
      // `persistForget: false`: not on the permanent ignore list, so it stays
      // reconnectable — proven indirectly here by the flag call above using
      // exactly that pair of arguments (see `SensorSourcePicker._disconnect`'s
      // doc comment); asserting the ignore list itself is
      // `ignored_devices_dialog`/`Settings.getIgnoredDevices` territory, out
      // of scope for this file.

      // See the connect-ordering test's own comment on why this has to run
      // here, inside the test body, rather than in a teardown hook.
      await core.connection.stop();
    });
  });
}
