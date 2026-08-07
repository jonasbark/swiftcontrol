import 'package:bike_control/bluetooth/devices/proxy/proxy_device.dart';
import 'package:bike_control/bluetooth/wifi_trainer_scanner.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ProxyDevice.mdnsSerialNumberFor', () {
    test('is always the 9 characters Wahoo clients expect', () {
      expect(ProxyDevice.mdnsSerialNumberFor('A0:F2:62:C3:8A:E0'), hasLength(9));
      expect(
        ProxyDevice.mdnsSerialNumberFor(WifiTrainerScanner.deviceIdFor('KICKR CORE 3F46')),
        hasLength(9),
      );
    });

    test('drops the dircon:// scheme so WiFi trainers keep their identity', () {
      // `dircon://` is itself exactly 9 characters, so slicing the raw device
      // id produced the scheme and nothing else for every WiFi trainer.
      final serial = ProxyDevice.mdnsSerialNumberFor(
        WifiTrainerScanner.deviceIdFor('KICKR CORE 3F46'),
      );

      expect(serial, isNot('dircon://'));
      expect(serial, startsWith('KICKR'));
    });

    test('gives two different WiFi trainers two different serials', () {
      final a = ProxyDevice.mdnsSerialNumberFor(WifiTrainerScanner.deviceIdFor('KICKR CORE 3F46'));
      final b = ProxyDevice.mdnsSerialNumberFor(WifiTrainerScanner.deviceIdFor('Wahoo KICKR 1A2B'));

      expect(a, isNot(b));
    });

    test('pads a short name instead of throwing', () {
      expect(ProxyDevice.mdnsSerialNumberFor(WifiTrainerScanner.deviceIdFor('Bike')), hasLength(9));
    });

    test('leaves BLE device ids on their existing derivation', () {
      // Unchanged behaviour: strip dashes, take the first 9 characters.
      expect(
        ProxyDevice.mdnsSerialNumberFor('95E042B7-1337-039E-C35F-C7095776F2D3'),
        '95E042B71',
      );
      expect(ProxyDevice.mdnsSerialNumberFor('A0:F2:62:C3:8A:E0'), 'A0:F2:62:');
    });
  });
}
