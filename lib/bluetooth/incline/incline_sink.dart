/// A destination that can set the incline (0.01% signed).
abstract class InclineSink {
  /// Writes the incline. Returns true if a write was issued.
  Future<bool> writeInclineRaw(int grade001Pct);

  /// True when this sink should follow the auto sim grade. A direct Climb
  /// device returns false while in manual hold; the relay sink is always true.
  bool get followsGrade;
}
