import 'package:bike_control/widgets/controller/steering_wheel_gauge.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('steerSideFor', () {
    test('positive angle past threshold ⇒ left (matches _applyPWMSteering)', () {
      expect(steerSideFor(8, 5), SteerSide.left);
    });
    test('negative angle past threshold ⇒ right', () {
      expect(steerSideFor(-8, 5), SteerSide.right);
    });
    test('within threshold ⇒ none', () {
      expect(steerSideFor(4, 5), SteerSide.none);
      expect(steerSideFor(-5, 5), SteerSide.none); // boundary is inclusive-neutral
      expect(steerSideFor(5, 5), SteerSide.none); // positive boundary inclusive-neutral
    });
  });
}
