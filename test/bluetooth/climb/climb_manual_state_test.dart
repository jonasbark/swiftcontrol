import 'package:bike_control/bluetooth/climb/climb_manual_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ClimbManualState', () {
    test('starts in auto mode at 0', () {
      final s = ClimbManualState();
      expect(s.mode, ClimbMode.auto);
      expect(s.grade001, 0);
    });

    test('increase enters manual and steps up by 1% (100)', () {
      final s = ClimbManualState();
      s.increase();
      expect(s.mode, ClimbMode.manual);
      expect(s.grade001, 100);
      s.increase();
      expect(s.grade001, 200);
    });

    test('decrease enters manual and steps down by 1%', () {
      final s = ClimbManualState();
      s.decrease();
      expect(s.mode, ClimbMode.manual);
      expect(s.grade001, -100);
    });

    test('zero enters manual at 0', () {
      final s = ClimbManualState()..increase();
      s.zero();
      expect(s.mode, ClimbMode.manual);
      expect(s.grade001, 0);
    });

    test('setAuto returns to auto', () {
      final s = ClimbManualState()..increase();
      s.setAuto();
      expect(s.mode, ClimbMode.auto);
    });

    test('clamps manual grade to the Climb range', () {
      final s = ClimbManualState();
      for (var i = 0; i < 40; i++) s.increase();
      expect(s.grade001, 2000); // +20%
      for (var i = 0; i < 60; i++) s.decrease();
      expect(s.grade001, -1000); // -10%
    });
  });
}
