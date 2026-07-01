import 'package:bike_control/bluetooth/incline/incline_manual_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('InclineManualState', () {
    test('starts in auto mode at 0', () {
      final s = InclineManualState();
      expect(s.mode, InclineMode.auto);
      expect(s.grade001, 0);
    });

    test('increase enters manual and steps up by 1% (100)', () {
      final s = InclineManualState();
      s.increase();
      expect(s.mode, InclineMode.manual);
      expect(s.grade001, 100);
      s.increase();
      expect(s.grade001, 200);
    });

    test('decrease enters manual and steps down by 1%', () {
      final s = InclineManualState();
      s.decrease();
      expect(s.mode, InclineMode.manual);
      expect(s.grade001, -100);
    });

    test('zero enters manual at 0', () {
      final s = InclineManualState()..increase();
      s.zero();
      expect(s.mode, InclineMode.manual);
      expect(s.grade001, 0);
    });

    test('setAuto returns to auto', () {
      final s = InclineManualState()..increase();
      s.setAuto();
      expect(s.mode, InclineMode.auto);
    });

    test('clamps manual grade to the incline range', () {
      final s = InclineManualState();
      for (var i = 0; i < 40; i++) s.increase();
      expect(s.grade001, 2000); // +20%
      for (var i = 0; i < 60; i++) s.decrease();
      expect(s.grade001, -1000); // -10%
    });
  });
}
