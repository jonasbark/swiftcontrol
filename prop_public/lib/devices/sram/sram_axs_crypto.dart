//INFO: This is a stub - contact me if you need the full implementation.
//
// The full implementation is the SRAM AES-EAX authenticated cipher. All
// bodies here are stubbed — no cryptographic logic is exposed.

import 'dart:typed_data';

class SramEax {
  SramEax._();

  static bool isFrame(Uint8List frame) => false;

  static Uint8List? decrypt(Uint8List key, Uint8List frame) => null;

  static Uint8List encrypt(Uint8List key, Uint8List plaintext, Uint8List nonce) => Uint8List(0);

  static Uint8List randomNonce() => Uint8List(0);
}
