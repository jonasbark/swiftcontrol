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

    // Fix round 1, Finding 1: ProxyDevice's own detection rule
    // (lib/bluetooth/devices/proxy/proxy_device.dart) matches any scan result
    // advertising the Cycling Power Service — the exact same 0x1818 UUID as
    // BleSensorSource.cyclingPowerServiceUuid — unconditionally, via
    // containsAny with no name gating, and it sits earlier in the non-web
    // switch than a plain service-based power rule is allowed to (staying
    // after it is what protects real DirCon-bridged trainers). A first
    // attempt at this task placed only a broad, name-unaware rule after
    // ProxyDevice, which made it permanently unreachable there: this group
    // proves the actual fix — a second, narrow rule placed BEFORE the
    // ProxyDevice branch, gated on both explicit opt-in and a name already
    // known to be a power meter (BluetoothDevice._isKnownPowerMeterName,
    // built from the same _ignoredNames list the exclusion below uses, so the
    // two cannot drift).
    test('an opted-in known power meter resolves to BlePowerDevice, not ProxyDevice', () async {
      final scan = BleDevice(
        deviceId: 'pm-1',
        name: 'ASSIOMA DUO-1234',
        services: [BleSensorSource.cyclingPowerServiceUuid],
      );

      await core.settings.setPowerMeterOptIn(true);

      expect(BluetoothDevice.fromScanResult(scan), isA<BlePowerDevice>());
    });

    test('the same known power meter name is hidden (null) when not opted in', () {
      final scan = BleDevice(
        deviceId: 'pm-2',
        name: 'ASSIOMA DUO-5678',
        services: [BleSensorSource.cyclingPowerServiceUuid],
      );

      expect(core.settings.getPowerMeterOptIn(), isFalse);
      expect(BluetoothDevice.fromScanResult(scan), isNull);
    });

    // The test that proves existing trainers are unaffected: a device
    // advertising bare Cycling Power Service whose name is NOT a known power
    // meter — e.g. a power-only trainer with no FTMS — must keep resolving to
    // ProxyDevice exactly as it did before this task, opt-in or not. The
    // narrow rule's name gate is what keeps it out of BlePowerDevice's way.
    test('a CPS advertiser with a non-power-meter name still resolves to ProxyDevice', () async {
      final scan = BleDevice(
        deviceId: 'trainer-cps-1',
        name: 'Stages 1234',
        services: [BleSensorSource.cyclingPowerServiceUuid],
      );

      expect(core.settings.getPowerMeterOptIn(), isFalse);
      expect(BluetoothDevice.fromScanResult(scan), isA<ProxyDevice>());

      // Holds even opted in — the name gate, not the opt-in flag, is what
      // protects this device.
      await core.settings.setPowerMeterOptIn(true);

      expect(BluetoothDevice.fromScanResult(scan), isA<ProxyDevice>());
    });
  });
}
