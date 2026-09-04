import 'dart:typed_data';

import 'package:bike_control/bluetooth/devices/sensors/ble_heart_rate_device.dart';
import 'package:bike_control/services/sensors/ble_sensor_source.dart';
import 'package:bike_control/services/sensors/sensor_quantity.dart';
import 'package:bike_control/utils/actions/base_actions.dart';
import 'package:bike_control/utils/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:universal_ble/universal_ble.dart';

BleHeartRateDevice _device() => BleHeartRateDevice(BleDevice(deviceId: 'hr-1', name: 'TICKR 1234'));

void main() {
  // Constructing a BluetoothDevice with an empty availableButtons list
  // touches core.actionHandler (BaseDevice's ctor probes the current
  // keymap) — same requirement as every other device-detection test.
  core.actionHandler = StubActions();

  test('routes a measurement notification into its source', () async {
    final device = _device();

    await device.processCharacteristic(
      BleSensorSource.heartRateMeasurementUuid,
      Uint8List.fromList([0x00, 150]),
    );

    expect(device.source.readingFor(SensorQuantity.heartRate).value!.value, 150);
  });

  test('ignores a notification on an unrelated characteristic', () async {
    final device = _device();

    await device.processCharacteristic(
      '00002a19-0000-1000-8000-00805f9b34fb', // battery level
      Uint8List.fromList([0x00, 99]),
    );

    expect(device.source.readingFor(SensorQuantity.heartRate).value, isNull);
  });

  test('matches the characteristic case-insensitively', () async {
    final device = _device();

    await device.processCharacteristic(
      BleSensorSource.heartRateMeasurementUuid.toUpperCase(),
      Uint8List.fromList([0x00, 141]),
    );

    expect(device.source.readingFor(SensorQuantity.heartRate).value!.value, 141);
  });

  test('the source is identified by the device id, so a selection can be persisted', () {
    final device = _device();

    expect(device.source.id, 'hr-1');
    expect(device.source.provides, {SensorQuantity.heartRate});
  });

  test('handleServices throws a named error when the strap has no heart rate service', () async {
    final device = _device();

    expect(
      () => device.handleServices(const <BleService>[]),
      throwsA(isA<Exception>()),
    );
  });
}
