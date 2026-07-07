import 'dart:typed_data';
import 'package:bike_control/bluetooth/devices/sram/sram_ble_transport.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:universal_ble/universal_ble.dart';

BleService _svc(String uuid, List<BleCharacteristic> chars) => BleService(uuid, chars);

BleCharacteristic _char(String uuid, List<CharacteristicProperty> props) =>
    BleCharacteristic(uuid, props, const []);

void main() {
  test('lists read+write characteristics only', () {
    final services = [
      _svc('d905ee51-90aa-4c7c-b036-1e01fb8eb7ee', [
        _char('d9050028-90aa-4c7c-b036-1e01fb8eb7ee',
            [CharacteristicProperty.read, CharacteristicProperty.write]),
        _char('d9050054-90aa-4c7c-b036-1e01fb8eb7ee', [CharacteristicProperty.notify]),
      ]),
    ];
    final t = SramBleTransport('dev1', services);
    expect(t.readWriteCharacteristics(), ['d9050028-90aa-4c7c-b036-1e01fb8eb7ee']);
  });

  test('notifications stream delivers pumped values', () async {
    final t = SramBleTransport('dev1', const []);
    final char = 'd905ee52-90aa-4c7c-b036-1e01fb8eb7ee';
    final future = t.notifications(char).first;
    t.onNotification(char, Uint8List.fromList([1, 2, 3]));
    expect(await future, [1, 2, 3]);
  });
}
