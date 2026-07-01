import 'package:bike_control/bluetooth/devices/elite/elite_rizer_protocol.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('rizerInclineToBytes', () {
    test('encodes 0.01% grade to 0x0a + int16 LE of percent*10', () {
      expect(rizerInclineToBytes(0), [0x0a, 0x00, 0x00]);      // 0%
      expect(rizerInclineToBytes(600), [0x0a, 0x3c, 0x00]);    // +6% -> 60
      expect(rizerInclineToBytes(-1000), [0x0a, 0x9c, 0xff]);  // -10% -> -100
    });
    test('clamps to the Rizer range (-10% .. +20%)', () {
      expect(rizerInclineToBytes(9000), rizerInclineToBytes(2000));   // +20% -> 200
      expect(rizerInclineToBytes(-9000), rizerInclineToBytes(-1000)); // -10% -> -100
      expect(rizerInclineToBytes(2000), [0x0a, 0xc8, 0x00]);          // +20% -> 200 = 0x00c8
    });
    test('exposes the service + char UUIDs', () {
      expect(eliteRizerServiceUuid, '347b0001-7635-408b-8918-8ff3949ce592');
      expect(eliteRizerWriteCharacteristicUuid, '347b0020-7635-408b-8918-8ff3949ce592');
      expect(eliteRizerSteeringCharacteristicUuid, '347b0030-7635-408b-8918-8ff3949ce592');
    });
  });
}
