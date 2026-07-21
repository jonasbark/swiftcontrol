//INFO: This is a stub - contact me if you need the full implementation.
//
// The full implementation maps a shifter's (deviceType, model) to its buttons
// and their human names. This stub returns generic placeholders.

class SramShifterButtons {
  SramShifterButtons._();

  /// Stubbed: a single paddle.
  static List<int> masksFor(int? deviceType, int? model) => const [1];

  /// Stubbed: generic label.
  static String nameFor(int? deviceType, int? model, int mask) => 'Button 0x${mask.toRadixString(16)}';
}
