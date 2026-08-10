import 'dart:typed_data';

import 'package:bike_control/bluetooth/devices/bluetooth_device.dart';
import 'package:bike_control/bluetooth/devices/sram/sram_axs.dart';
import 'package:bike_control/utils/actions/base_actions.dart';
import 'package:bike_control/utils/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prop/prop.dart' show SramAdvertisement;
import 'package:prop/testing.dart';
import 'package:universal_ble/universal_ble.dart';

BleDevice _sram({Uint8List? record}) => BleDevice(
      deviceId: 'x',
      name: 'SRAM 42',
      services: const [SramAdvertisement.serviceUuid128],
      serviceData: record == null ? const {} : {SramAdvertisement.serviceUuid128: record},
    );

void main() {
  // fromScanResult builds a BluetoothDevice whose BaseDevice constructor reads
  // core.actionHandler.supportedApp — stub it. Detection never touches
  // core.settings for the SRAM service path, so no prefs setup is needed.
  core.actionHandler = StubActions();

  test('a bare shifter advert is rejected — only the RD connects', () {
    final device = BluetoothDevice.fromScanResult(_sram(record: SramAdvertFixtures.shifter()));
    expect(device, isNull);
  });

  test('a rear-derailleur advert yields a SramAxs', () {
    final device = BluetoothDevice.fromScanResult(_sram(record: SramAdvertFixtures.rearDerailleur()));
    expect(device, isA<SramAxs>());
  });

  test('a present-but-too-short record falls back to accept (SramAxs)', () {
    final device = BluetoothDevice.fromScanResult(_sram(record: SramAdvertFixtures.tooShort()));
    expect(device, isA<SramAxs>());
  });

  test('no service data falls back to accept (SramAxs)', () {
    final device = BluetoothDevice.fromScanResult(_sram());
    expect(device, isA<SramAxs>());
  });
}
