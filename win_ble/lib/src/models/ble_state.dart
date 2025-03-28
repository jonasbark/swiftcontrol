// ignore_for_file: constant_identifier_names

/// [BleState] is an Enum to represent current state of BLE
enum BleState {
  On,
  Off,
  Unknown,
  Disabled,
  Unsupported;

  static BleState parse(String state) {
    return switch (state.toLowerCase()) {
      "on" => BleState.On,
      "off" => BleState.Off,
      "disabled" => BleState.Disabled,
      "unsupported" => BleState.Unsupported,
      _ => BleState.Unknown
    };
  }
}
