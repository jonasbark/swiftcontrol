import 'dart:typed_data';

import 'package:bike_control/bluetooth/devices/bluetooth_device.dart';
import 'package:bike_control/bluetooth/devices/proxy/proxy_device.dart';
import 'package:bike_control/bluetooth/devices/sensors/ble_cadence_device.dart';
import 'package:bike_control/bluetooth/devices/sensors/ble_power_device.dart';
import 'package:bike_control/services/sensors/ble_sensor_source.dart';
import 'package:bike_control/services/sensors/sensor_quantity.dart';
import 'package:bike_control/utils/actions/base_actions.dart';
import 'package:bike_control/utils/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:universal_ble/universal_ble.dart';

BleCadenceDevice _cadenceDevice({String id = 'csc-1', String? name = 'CAD 7788'}) =>
    BleCadenceDevice(BleDevice(deviceId: id, name: name));

BlePowerDevice _powerDevice({String id = 'cps-1', String? name = 'Meter'}) =>
    BlePowerDevice(BleDevice(deviceId: id, name: name));

/// CSC frame with crank data only: flags 0x02, uint16 cum revs, uint16 event time.
List<int> _csc(int revs, int t1024) => [0x02, revs & 0xFF, (revs >> 8) & 0xFF, t1024 & 0xFF, (t1024 >> 8) & 0xFF];

void main() {
  // Constructing a BluetoothDevice with an empty availableButtons list
  // touches core.actionHandler (BaseDevice's ctor probes the current
  // keymap) — same requirement as every other device-detection test.
  core.actionHandler = StubActions();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    core.settings.prefs = await SharedPreferences.getInstance();
  });

  group('BleCadenceDevice', () {
    test('routes CSC notifications into its source', () async {
      final device = _cadenceDevice();

      await device.processCharacteristic(BleSensorSource.cscMeasurementUuid, Uint8List.fromList(_csc(10, 1024)));
      await device.processCharacteristic(BleSensorSource.cscMeasurementUuid, Uint8List.fromList(_csc(11, 2048)));

      expect(device.source.readingFor(SensorQuantity.cadence).value!.value, 60);
    });

    test('ignores a notification on an unrelated characteristic', () async {
      final device = _cadenceDevice();

      await device.processCharacteristic(
        '00002a19-0000-1000-8000-00805f9b34fb', // battery level
        Uint8List.fromList([0x00, 99]),
      );

      expect(device.source.readingFor(SensorQuantity.cadence).value, isNull);
    });

    test('the source is identified by the device id and provides only cadence', () {
      final device = _cadenceDevice();

      expect(device.source.id, 'csc-1');
      expect(device.source.provides, {SensorQuantity.cadence});
    });

    test('handleServices throws a named error when the sensor has no CSC service', () async {
      final device = _cadenceDevice();

      expect(
        () => device.handleServices(const <BleService>[]),
        throwsA(isA<Exception>()),
      );
    });

    // Same consent gate as BleHeartRateDevice: most BLE sensors accept only
    // one simultaneous connection, so an un-gated cadence sensor would sneak
    // into Connection.addDevices' auto-connect queue and steal itself away
    // from whatever app already has it.
    test('shouldAutoConnect is false until the rider explicitly connects it', () {
      final device = _cadenceDevice();

      expect(device.shouldAutoConnect, isFalse);
    });

    test('shouldAutoConnect flips true once the rider has explicitly connected this device id', () async {
      final device = _cadenceDevice();
      expect(device.shouldAutoConnect, isFalse);

      await core.settings.setSensorAutoConnect(device.device.deviceId, true);

      expect(device.shouldAutoConnect, isTrue);
    });

    test('is an Accessory, not a controller', () {
      final device = _cadenceDevice();

      expect(device, isA<Accessory>());
    });
  });

  group('BlePowerDevice', () {
    test('publishes power and claims cadence too', () async {
      final device = _powerDevice();

      await device.processCharacteristic(
        BleSensorSource.cyclingPowerMeasurementUuid,
        Uint8List.fromList([0x00, 0x00, 0xFA, 0x00]), // 250 W
      );

      expect(device.source.readingFor(SensorQuantity.power).value!.value, 250);
      expect(device.source.provides, {SensorQuantity.power, SensorQuantity.cadence});
    });

    test('ignores a notification on an unrelated characteristic', () async {
      final device = _powerDevice();

      await device.processCharacteristic(
        '00002a19-0000-1000-8000-00805f9b34fb', // battery level
        Uint8List.fromList([0x00, 99]),
      );

      expect(device.source.readingFor(SensorQuantity.power).value, isNull);
    });

    test('the source is identified by the device id', () {
      final device = _powerDevice();

      expect(device.source.id, 'cps-1');
    });

    test('handleServices throws a named error when the sensor has no Cycling Power service', () async {
      final device = _powerDevice();

      expect(
        () => device.handleServices(const <BleService>[]),
        throwsA(isA<Exception>()),
      );
    });

    test('shouldAutoConnect is false until the rider explicitly connects it', () {
      final device = _powerDevice();

      expect(device.shouldAutoConnect, isFalse);
    });

    test('is an Accessory, not a controller', () {
      final device = _powerDevice();

      expect(device, isA<Accessory>());
    });
  });

  group('detection', () {
    test('a cadence sensor with a plain name is detected via the CSC service', () {
      final scan = BleDevice(
        deviceId: 'csc-2',
        name: 'CAD 7788',
        services: [BleSensorSource.cscServiceUuid],
      );

      expect(BluetoothDevice.fromScanResult(scan), isA<BleCadenceDevice>());
    });

    // Only the specific `_ignoredNames` families are gated behind the opt-in
    // (see below) — every other power meter brand is exempt from that gate,
    // default settings and all. It still resolves to ProxyDevice rather than
    // BlePowerDevice here — see the comment on the group below — but it is
    // demonstrably not short-circuited to null by the name check.
    test('a power meter with a non-ignored name is not blocked by the opt-in gate', () {
      final scan = BleDevice(
        deviceId: 'cps-2',
        name: 'Stages 1234',
        services: [BleSensorSource.cyclingPowerServiceUuid],
      );

      expect(core.settings.getPowerMeterOptIn(), isFalse);
      expect(BluetoothDevice.fromScanResult(scan), isNotNull);
    });

    // Pre-existing collision, not introduced by this task: ProxyDevice's own
    // detection rule (lib/bluetooth/devices/proxy/proxy_device.dart) matches
    // any scan result advertising the Cycling Power Service — the exact same
    // 0x1818 UUID as BleSensorSource.cyclingPowerServiceUuid — with no name
    // gating at all, and it sits earlier in the switch than these new rules
    // are allowed to (the brief mandates staying after it, for good reason:
    // that's what protects real DirCon-bridged trainers). So a scan result
    // that looks like a standards-compliant power meter is indistinguishable
    // from ProxyDevice's own trigger, and ProxyDevice wins every time in the
    // non-web branch — BlePowerDevice's Cycling-Power-Service rule can only
    // ever fire on web, where there is no ProxyDevice case. CSC (0x1816) has
    // no such overlap, so BleCadenceDevice is unaffected (see the group
    // above). Flagged for a follow-up decision on ProxyDevice.proxyServiceUUIDs
    // rather than fixed here: narrowing it is out of scope for a task about
    // adding sensor devices, and reordering these new rules ahead of it would
    // reintroduce exactly the trainer-stealing regression this task exists to
    // avoid.
    test('a power meter is hidden from scans until the rider opts in', () async {
      final scan = BleDevice(
        deviceId: 'pm-1',
        name: 'ASSIOMA DUO-1234',
        services: [BleSensorSource.cyclingPowerServiceUuid],
      );

      expect(BluetoothDevice.fromScanResult(scan), isNull);

      await core.settings.setPowerMeterOptIn(true);

      expect(BluetoothDevice.fromScanResult(scan), isA<ProxyDevice>());
    });
  });
}
