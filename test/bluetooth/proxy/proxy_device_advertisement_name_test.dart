import 'package:bike_control/bluetooth/devices/proxy/proxy_device.dart';
import 'package:bike_control/utils/actions/base_actions.dart';
import 'package:bike_control/utils/core.dart';
import 'package:bike_control/utils/keymap/apps/rouvy.dart';
import 'package:bike_control/utils/keymap/apps/zwift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:universal_ble/universal_ble.dart';

/// The name and bind behaviour the bridge picks per trainer app. What each
/// endpoint advertises is covered in `prop`.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    core.settings.prefs = await SharedPreferences.getInstance();
    core.actionHandler = StubActions();
  });

  ProxyDevice deviceNamed(String? name) => ProxyDevice(BleDevice(deviceId: 'trainer', name: name));

  test('is the trainer name with a neutral suffix', () {
    core.settings.setTrainerApp(Rouvy());

    expect(deviceNamed('Wahoo KICKR 1EB7').rouvyAdvertisementName(), 'Wahoo KICKR 1EB7 - Bridge');
  });

  test('is neutral whatever the trainer is called', () {
    core.settings.setTrainerApp(Rouvy());

    for (final name in ['Wahoo KICKR 1EB7', 'BikeControl V2', 'bikecontrol', null, '']) {
      expect(
        deviceNamed(name).rouvyAdvertisementName()!.toLowerCase(),
        isNot(contains('bikecontrol')),
        reason: 'trainer named "$name"',
      );
    }
  });

  test('falls back to the bare suffix when the trainer has no usable name', () {
    core.settings.setTrainerApp(Rouvy());

    expect(deviceNamed(null).rouvyAdvertisementName(), 'Bridge');
    expect(deviceNamed('').rouvyAdvertisementName(), 'Bridge');
    expect(deviceNamed('BikeControl V2').rouvyAdvertisementName(), 'Bridge');
  });

  test('is not imposed on any other trainer app', () {
    core.settings.setTrainerApp(Zwift());

    expect(deviceNamed('Wahoo KICKR 1EB7').rouvyAdvertisementName(), isNull);
  });

  test('binds IPv4-only for Rouvy and dual-stack for everyone else', () {
    core.settings.setTrainerApp(Rouvy());
    expect(deviceNamed('Wahoo KICKR 1EB7').rouvyNeedsIPv4(), isTrue);

    core.settings.setTrainerApp(Zwift());
    expect(deviceNamed('Wahoo KICKR 1EB7').rouvyNeedsIPv4(), isFalse);
  });
}
