import 'package:bike_control/bluetooth/emulation/emulated_peripherals.dart';
import 'package:bike_control/services/sensors/ble_sensor_source.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the emulated strap advertises the heart rate service', () {
    final peripheral = heartRateStrapPeripheral();

    // Both halves matter: `services` is what a connected client discovers,
    // `advertisedServices` is what a filtered scan matches.
    expect(
      peripheral.services.map((s) => s.uuid.toLowerCase()),
      contains(BleSensorSource.heartRateServiceUuid),
    );
    expect(
      peripheral.advertisedServices,
      contains(BleSensorSource.heartRateServiceUuid),
    );
  });

  test('the emulated strap exposes the measurement characteristic', () {
    final peripheral = heartRateStrapPeripheral();

    final service = peripheral.services.firstWhere(
      (s) => s.uuid.toLowerCase() == BleSensorSource.heartRateServiceUuid,
    );

    expect(
      service.characteristics.map((c) => c.uuid.toLowerCase()),
      contains(BleSensorSource.heartRateMeasurementUuid),
    );
  });
}
