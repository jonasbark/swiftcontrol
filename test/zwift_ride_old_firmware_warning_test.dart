import 'package:bike_control/bluetooth/devices/bluetooth_device.dart';
import 'package:flutter_test/flutter_test.dart';

/// The "You may need to update the firmware" toast for the Zwift Ride must
/// only fire for genuinely old firmware. A modern Ride advertises TWO
/// manufacturer-data types — RIDE_LEFT_SIDE (→ a ZwiftRide device) and
/// RIDE_RIGHT_SIDE (deliberately mapped to null). The right-side advert
/// therefore builds no device, but it DOES expose the Zwift custom service,
/// so it must not be mistaken for old firmware (ticket ed826861, issue #2).
void main() {
  group('BluetoothDevice.isLikelyOldRideFirmware', () {
    test('true only when a Zwift Ride is unrecognized AND has no Zwift service', () {
      expect(
        BluetoothDevice.isLikelyOldRideFirmware(
          name: 'Zwift Ride',
          deviceRecognized: false,
          hasZwiftCustomService: false,
        ),
        isTrue,
      );
    });

    test('false for the right-side advert: unrecognized but exposes the Zwift service', () {
      expect(
        BluetoothDevice.isLikelyOldRideFirmware(
          name: 'Zwift Ride',
          deviceRecognized: false,
          hasZwiftCustomService: true,
        ),
        isFalse,
      );
    });

    test('false once a device was recognized', () {
      expect(
        BluetoothDevice.isLikelyOldRideFirmware(
          name: 'Zwift Ride',
          deviceRecognized: true,
          hasZwiftCustomService: false,
        ),
        isFalse,
      );
    });

    test('false for any other device name', () {
      expect(
        BluetoothDevice.isLikelyOldRideFirmware(
          name: 'Zwift Play',
          deviceRecognized: false,
          hasZwiftCustomService: false,
        ),
        isFalse,
      );
    });
  });
}
