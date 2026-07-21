//INFO: This is a stub - contact me if you need the full implementation.

import 'dart:async';
import 'dart:typed_data';

/// BLE seam for the SRAM protocol code. The app supplies a `universal_ble`
/// backed implementation; tests supply a fake.
abstract class SramTransport {
  Future<void> subscribe(String characteristic);
  Future<void> write(String characteristic, Uint8List data, {bool withoutResponse = false});
  Future<Uint8List> read(String characteristic);

  /// Notifications delivered on [characteristic] after [subscribe].
  Stream<Uint8List> notifications(String characteristic);

  /// UUIDs of characteristics that are both readable and writable.
  List<String> readWriteCharacteristics();
}

/// Buffers notification fragments and hands back exactly `count` bytes per
/// [take]. Stubbed.
class SramByteInbox {
  void add(Uint8List data) {}

  Future<Uint8List> take(int count) => throw UnimplementedError();
}

/// One reaction-config slot's trigger: parallel device-type / button-mask lists.
class SramReactionTrigger {
  const SramReactionTrigger(this.deviceTypes, this.buttonMasks);

  final List<int> deviceTypes;
  final List<int> buttonMasks;

  Map<String, dynamic> toJson() => {'device_types': deviceTypes, 'button_masks': buttonMasks};

  factory SramReactionTrigger.fromJson(Map<String, dynamic> json) => SramReactionTrigger(
        (json['device_types'] as List).cast<int>(),
        (json['button_masks'] as List).cast<int>(),
      );
}
