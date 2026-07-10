import 'package:bike_control/bluetooth/devices/elite/elite_rizer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('rizerSteerDecision', () {
    test('below threshold => center (null)', () {
      expect(rizerSteerDecision(5), null);
      expect(rizerSteerDecision(-9), null);
    });
    test('beyond +threshold => right, -threshold => left', () {
      expect(rizerSteerDecision(15)?.right, true);
      expect(rizerSteerDecision(-15)?.right, false);
    });
    test('levels scale with magnitude, clamped 1..MAX', () {
      expect(rizerSteerDecision(15)?.levels, 1);
      expect(rizerSteerDecision(100)?.levels, 5); // clamp to MAX
    });
  });
}
