import 'package:bike_control/bluetooth/devices/bluetooth_device.dart';
import 'package:bike_control/bluetooth/devices/zwift/constants.dart';
import 'package:bike_control/bluetooth/devices/zwift/zwift_click.dart';
import 'package:bike_control/utils/actions/base_actions.dart';
import 'package:bike_control/utils/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:universal_ble/universal_ble.dart';
import 'dart:typed_data';

BleDevice _zwiftClick() => BleDevice(
  deviceId: 'click-v1',
  name: 'Zwift Click',
  manufacturerDataList: [
    ManufacturerData(ZwiftConstants.ZWIFT_MANUFACTURER_ID, Uint8List.fromList([ZwiftConstants.BC1])),
  ],
  services: [ZwiftConstants.ZWIFT_CUSTOM_SERVICE_UUID.toLowerCase()],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    core.actionHandler = StubActions();
    core.settings.prefs = await SharedPreferences.getInstance();
  });

  test('an ordinary controller opts into auto-connect', () {
    final device = BluetoothDevice.fromScanResult(_zwiftClick());
    expect(device, isA<ZwiftClick>());
    expect(device!.shouldAutoConnect, isTrue);
  });
}
