import 'dart:typed_data';

/// Elite Rizer proprietary incline control (reverse-engineered; described on its
/// own terms). The Rizer is a standalone incline + steering BLE device.
const String eliteRizerServiceUuid = '347b0001-7635-408b-8918-8ff3949ce592';
const String eliteRizerWriteCharacteristicUuid = '347b0020-7635-408b-8918-8ff3949ce592';
const String eliteRizerStatusCharacteristicUuid = '347b0021-7635-408b-8918-8ff3949ce592';
const String eliteRizerInclineCharacteristicUuid = '347b0022-7635-408b-8918-8ff3949ce592';
const String eliteRizerSteeringCharacteristicUuid = '347b0030-7635-408b-8918-8ff3949ce592';

const int eliteRizerSetInclineOpcode = 0x0a;

/// Rizer tilt range in 0.01% units (-10% .. +20%).
const int kEliteRizerMinGrade001 = -1000;
const int kEliteRizerMaxGrade001 = 2000;

/// Encodes an incline (0.01% signed) into `[0x0a, lo, hi]`, int16 LE of
/// tenths-of-a-percent (percent * 10). Clamped to the Rizer range. Gain = 1.0.
Uint8List rizerInclineToBytes(int grade001Pct) {
  final clamped = grade001Pct.clamp(kEliteRizerMinGrade001, kEliteRizerMaxGrade001);
  final tenths = (clamped / 10).round(); // 0.01% -> 0.1%
  final u = tenths & 0xFFFF;
  return Uint8List.fromList([eliteRizerSetInclineOpcode, u & 0xFF, (u >> 8) & 0xFF]);
}
