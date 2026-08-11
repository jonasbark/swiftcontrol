//INFO: This is a stub - contact me if you need the full implementation.
//
// The full implementation owns the SRAM session key, decrypts button events
// and reads/writes the on-device reaction config. This stub keeps the public
// surface so the app compiles.

import 'dart:typed_data';

import 'sram_axs_transport.dart';

/// A single decoded press: which controller (serial + device_type) and which
/// button (mask). Any field may be null in degraded operation.
class SramPress {
  const SramPress({this.controllerSerial, this.buttonMask, this.deviceType});
  final int? controllerSerial;
  final int? buttonMask;

  /// The pressing controller's device_type (0 = left shifter, 1 = right, …).
  final int? deviceType;
}

/// Per-device façade over the SRAM protocol units.
class SramAxsLogic {
  SramAxsLogic(this.transport);

  final SramTransport transport;

  Uint8List? _key;

  Uint8List? get sessionKey => _key;
  bool get isBonded => _key != null;

  void seedKey(Uint8List? key) => _key = key;

  Future<Uint8List> bond() => throw UnimplementedError();

  Future<void> ensureBonded() async {}

  void onComponentEvent(Uint8List plaintext) {}

  Future<SramPress> handleTrigger() async => const SramPress();

  Future<Map<String, SramReactionTrigger>> backupConfig() async => {};

  Future<void> disableShifting() async {}

  Future<void> restoreConfig(Map<String, SramReactionTrigger> saved) async {}
}
