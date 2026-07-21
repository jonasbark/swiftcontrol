//INFO: This is a stub - contact me if you need the full implementation.
//
// The full implementation parses the SRAM AXS advertising "device record".
// Values below are FAKE placeholders; [parse] is stubbed.

import 'dart:typed_data';

/// A SRAM AXS component identified from its advertising "device record".
class SramDeviceInfo {
  const SramDeviceInfo({required this.serial, this.model, this.deviceType});

  final int serial;
  final int? model;
  final int? deviceType;

  int? get effectiveType => deviceType;

  /// Stubbed classification.
  bool get isRearDerailleur => false;
}

/// Parses the advertising "device record" that identifies a SRAM AXS
/// component before connecting.
class SramAdvertisement {
  SramAdvertisement._();

  // FAKE placeholder service UUIDs.
  static const int serviceUuid16 = 0x0000;
  static const String serviceUuid128 = '00000000-0000-0000-0000-000000000000';

  /// Stubbed: returns null.
  static SramDeviceInfo? parse(Uint8List record) => null;
}
