import 'package:bike_control/bluetooth/wifi_trainer_scanner.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prop/prop.dart';

void main() {
  group('mdnsSerialNumber', () {
    test('is all digits, as Wahoo-protocol clients require', () {
      // Clients parse this TXT value as a number, so anything sliced out of a
      // MAC or a UUID ('A0:F2:62:', '95E042B71') breaks them.
      for (final id in [
        'A0:F2:62:C3:8A:E0',
        '95E042B7-1337-039E-C35F-C7095776F2D3',
        WifiTrainerScanner.deviceIdFor('KICKR CORE 3F46'),
      ]) {
        expect(mdnsSerialNumber(id), matches(RegExp(r'^\d+$')), reason: id);
      }
    });

    test('gives two different WiFi trainers two different serials', () {
      // WiFi trainer ids share a `dircon://` prefix, so a derivation that only
      // looked at the first characters gave every one of them the same serial.
      final a = mdnsSerialNumber(WifiTrainerScanner.deviceIdFor('KICKR CORE 3F46'));
      final b = mdnsSerialNumber(WifiTrainerScanner.deviceIdFor('Wahoo KICKR 1A2B'));

      expect(a, isNot(b));
    });

    test('is stable, so a client still recognises the trainer it paired with', () {
      final id = WifiTrainerScanner.deviceIdFor('KICKR CORE 3F46');

      expect(mdnsSerialNumber(id), mdnsSerialNumber(id));
    });

    test('handles a short id instead of throwing', () {
      expect(mdnsSerialNumber(WifiTrainerScanner.deviceIdFor('Bike')), matches(RegExp(r'^\d+$')));
    });
  });
}
