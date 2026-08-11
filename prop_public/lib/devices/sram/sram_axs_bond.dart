//INFO: This is a stub - contact me if you need the full implementation.
//
// The full implementation runs the SRAM `srambond` Diffie–Hellman handshake.

import 'dart:typed_data';

class SramBondException implements Exception {
  SramBondException(this.message);
  final String message;
  @override
  String toString() => 'SramBondException: $message';
}

/// The `srambond` V1 finite-field Diffie–Hellman handshake. The handshake
/// itself is stubbed; the BigInt ↔ 16-byte helpers are kept.
class SramBond {
  SramBond._();

  static Uint8List bigIntTo16(BigInt v) {
    final out = Uint8List(16);
    var t = v;
    for (var i = 15; i >= 0; i--) {
      out[i] = (t & BigInt.from(0xff)).toInt();
      t = t >> 8;
    }
    return out;
  }

  static BigInt bigIntFrom(Uint8List bytes) {
    var v = BigInt.zero;
    for (final b in bytes) {
      v = (v << 8) | BigInt.from(b);
    }
    return v;
  }
}
