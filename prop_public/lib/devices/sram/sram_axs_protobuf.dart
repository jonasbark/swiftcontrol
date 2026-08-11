//INFO: This is a stub - contact me if you need the full implementation.
//
// The full implementation encodes/decodes the SRAM reaction-config protobuf.
// All bodies here are stubbed.

import 'dart:typed_data';

class SramProtobuf {
  SramProtobuf._();

  static Map<int, int> parseVarints(Uint8List data) => const {};

  static (List<int>, List<int>) parseReactionConfig(Uint8List data) => (const [], const []);

  static Uint8List encodeReactionConfig(List<int> deviceTypes, List<int> buttonMasks, int token) => Uint8List(0);
}
