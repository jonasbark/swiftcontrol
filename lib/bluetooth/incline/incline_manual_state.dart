enum InclineMode { auto, manual }

/// Manual incline range in 0.01% units (-10% .. +20%) — the UI bound for manual
/// nudging. Per-device WIRE clamps live in each device's encoder.
const int kInclineManualMinGrade001 = -1000;
const int kInclineManualMaxGrade001 = 2000;

/// Pure auto/manual state for an incline device. `auto` follows the sim grade;
/// `manual` holds a user-set incline. All values are 0.01% signed.
class InclineManualState {
  InclineMode mode = InclineMode.auto;
  int grade001 = 0;

  /// One button press moves the held incline by 1% (100 units).
  static const int stepGrade001 = 100;

  void increase() => _manualDelta(stepGrade001);
  void decrease() => _manualDelta(-stepGrade001);

  void zero() {
    mode = InclineMode.manual;
    grade001 = 0;
  }

  void setAuto() => mode = InclineMode.auto;

  void _manualDelta(int delta) {
    mode = InclineMode.manual;
    grade001 = (grade001 + delta).clamp(kInclineManualMinGrade001, kInclineManualMaxGrade001);
  }
}
