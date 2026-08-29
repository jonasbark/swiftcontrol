// Detecting a Zwift Ride whose firmware is newer than the last supported
// version (>1.2.0 = the server-locked firmware that stops the Ride working
// with third-party apps). The check must tolerate extra version components and
// must NOT fire for ZwiftRide subclasses like the Click v2.
import 'package:bike_control/bluetooth/devices/zwift/firmware_support.dart';
import 'package:bike_control/bluetooth/devices/zwift/zwift_clickv2.dart';
import 'package:bike_control/bluetooth/devices/zwift/zwift_ride.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:universal_ble/universal_ble.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('isFirmwareBeyondSupported', () {
    test('firmware equal to the supported version is not beyond', () {
      expect(isFirmwareBeyondSupported('1.2.0', '1.2.0'), isFalse);
    });

    test('a patch bump past supported is beyond', () {
      expect(isFirmwareBeyondSupported('1.2.1', '1.2.0'), isTrue);
    });

    test('a minor bump past supported is beyond', () {
      expect(isFirmwareBeyondSupported('1.3.0', '1.2.0'), isTrue);
    });

    test('a fourth build component is ignored: 1.2.0.24 is not beyond 1.2.0', () {
      expect(isFirmwareBeyondSupported('1.2.0.24', '1.2.0'), isFalse);
    });

    test('older firmware is not beyond', () {
      expect(isFirmwareBeyondSupported('1.1.0', '1.2.0'), isFalse);
    });

    test('null, empty or unparseable firmware is never beyond (fail safe)', () {
      expect(isFirmwareBeyondSupported(null, '1.2.0'), isFalse);
      expect(isFirmwareBeyondSupported('', '1.2.0'), isFalse);
      expect(isFirmwareBeyondSupported('unknown', '1.2.0'), isFalse);
    });
  });

  group('ZwiftRide.hasUnsupportedFirmware', () {
    ZwiftRide ride(String? fw) =>
        ZwiftRide(BleDevice(deviceId: 'zr', name: 'Zwift Ride'))..firmwareVersion = fw;

    test('a Ride on firmware past 1.2.0 is flagged', () {
      expect(ZwiftRide.hasUnsupportedFirmware(ride('1.3.0')), isTrue);
    });

    test('a Ride on the last good 1.2.0 is not flagged', () {
      expect(ZwiftRide.hasUnsupportedFirmware(ride('1.2.0')), isFalse);
    });

    test('a Ride with unknown firmware is not flagged', () {
      expect(ZwiftRide.hasUnsupportedFirmware(ride(null)), isFalse);
    });

    test('a Click v2 (ZwiftRide subclass) on 1.3.0 does NOT trigger the Ride prompt', () {
      final clickV2 = ZwiftClickV2(BleDevice(deviceId: 'c2', name: 'Zwift Click'))
        ..firmwareVersion = '1.3.0';
      expect(ZwiftRide.hasUnsupportedFirmware(clickV2), isFalse);
    });
  });
}
