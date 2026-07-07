import 'dart:typed_data';

import 'package:bike_control/bluetooth/devices/bluetooth_device.dart';
import 'package:bike_control/bluetooth/devices/sram/sram_axs.dart';
import 'package:bike_control/utils/actions/base_actions.dart';
import 'package:bike_control/utils/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:universal_ble/universal_ble.dart';

const String _fe51 = '0000fe51-0000-1000-8000-00805f9b34fb';

BleDevice _sram({Map<String, Uint8List>? serviceData}) => BleDevice(
      deviceId: 'x',
      name: 'SRAM 42',
      services: const [_fe51],
      serviceData: serviceData ?? const {},
    );

void main() {
  // fromScanResult builds a BluetoothDevice whose BaseDevice constructor reads
  // core.actionHandler.supportedApp — stub it. Detection never touches
  // core.settings for the SRAM service path, so no prefs setup is needed.
  core.actionHandler = StubActions();

  test('a bare shifter advert (deviceType 0) is rejected — only the RD connects', () {
    // flags 0x01 (flags2 present), flags2 0x02 (deviceType byte), serial 100, type 0.
    final record = Uint8List.fromList([0x01, 0x02, 0x64, 0x00, 0x00, 0x00, 0x00]);
    final device = BluetoothDevice.fromScanResult(_sram(serviceData: {_fe51: record}));
    expect(device, isNull);
  });

  test('the §2.3 rear-derailleur record (type 129) yields a SramAxs', () {
    // 4D 03 98 2B 97 55 E9 03 02 29 00 81 → deviceType 0x81 = 129 (RD).
    final record = Uint8List.fromList([0x4D, 0x03, 0x98, 0x2B, 0x97, 0x55, 0xE9, 0x03, 0x02, 0x29, 0x00, 0x81]);
    final device = BluetoothDevice.fromScanResult(_sram(serviceData: {_fe51: record}));
    expect(device, isA<SramAxs>());
  });

  test('a present-but-too-short record falls back to accept (SramAxs)', () {
    final device = BluetoothDevice.fromScanResult(_sram(serviceData: {_fe51: Uint8List.fromList([0x01])}));
    expect(device, isA<SramAxs>());
  });

  test('no service data falls back to accept (SramAxs)', () {
    final device = BluetoothDevice.fromScanResult(_sram());
    expect(device, isA<SramAxs>());
  });
}
