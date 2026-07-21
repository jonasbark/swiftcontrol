//INFO: This is a stub - contact me if you need the full implementation.
//
// All values below are FAKE placeholders. The real SRAM AXS protocol
// constants (UUIDs, DH group parameters, protobuf field numbers) live in the
// full package.

import 'dart:typed_data';

class SramAxs {
  SramAxs._();

  static const String _base = '-0000-0000-0000-000000000000';

  static const String bondService = '00000000$_base';
  static const String bondChar = '00000001$_base';
  static const String tokenChar = '00000002$_base';
  static const String controlTriggerChar = '00000003$_base';
  static const String gearChar = '00000004$_base';
  static const String componentEventChar = '00000005$_base';

  static const int dhG = 0;
  static final BigInt dhN = BigInt.zero;

  static final Uint8List bondInitToken = Uint8List(16);

  static const int bondAck = 0x00;

  static const int fieldToken = 0;
  static const int fieldControllerDeviceType = 0;
  static const int fieldButtonMask = 0;
  static const int fieldGear = 0;
  static const int fieldCassette = 0;
  static const int fieldTriggerDeviceType = 0;
  static const int fieldTriggerButtonMask = 0;
  static const int fieldTrigger = 0;

  static const int paddleMask = 1;
}
