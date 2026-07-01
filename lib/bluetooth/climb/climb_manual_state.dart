import 'package:prop/utils/wahoo_climb.dart';

enum ClimbMode { auto, manual }

/// Pure auto/manual state for the KICKR Climb. `auto` follows the sim grade;
/// `manual` holds a user-set incline. All values are 0.01% signed.
class ClimbManualState {
  ClimbMode mode = ClimbMode.auto;
  int grade001 = 0;

  /// One button press moves the held incline by 1% (100 units).
  static const int stepGrade001 = 100;

  void increase() => _manualDelta(stepGrade001);
  void decrease() => _manualDelta(-stepGrade001);

  void zero() {
    mode = ClimbMode.manual;
    grade001 = 0;
  }

  void setAuto() => mode = ClimbMode.auto;

  void _manualDelta(int delta) {
    mode = ClimbMode.manual;
    grade001 = (grade001 + delta).clamp(kWahooClimbMinGrade001, kWahooClimbMaxGrade001);
  }
}
