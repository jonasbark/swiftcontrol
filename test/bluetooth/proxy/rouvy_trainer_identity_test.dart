import 'package:bike_control/bluetooth/devices/proxy/proxy_device.dart';
import 'package:bike_control/utils/actions/base_actions.dart';
import 'package:bike_control/utils/core.dart';
import 'package:bike_control/utils/keymap/apps/rouvy.dart';
import 'package:bike_control/utils/keymap/apps/zwift.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prop/emulators/definitions/fitness_bike_definition.dart';
import 'package:prop/emulators/definitions/zwift_emulator_definition.dart';
import 'package:prop/emulators/dircon_emulator.dart';
import 'package:prop/utils/constants.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:universal_ble/universal_ble.dart';

/// What the trainer and controller endpoints advertise for Rouvy. The two
/// roles cannot share an endpoint there; reasoning in `prop`.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const zwiftPlay = FtmsMdnsConstants.ZWIFT_PLAY_SERVICE_UUID_LC;
  const zwiftRide = FtmsMdnsConstants.ZWIFT_RIDE_CUSTOM_SERVICE_UUID;
  const marker = FtmsMdnsConstants.BIKE_CONTROL_MARKER_SERVICE_UUID;
  const deviceInformation = '0000180a-0000-1000-8000-00805f9b34fb';

  final trainerServices = [
    BleService(FitnessBikeDefinition.FITNESS_MACHINE_SERVICE_UUID, []),
    BleService(deviceInformation, []),
  ];

  FitnessBikeDefinition buildFbd() => FitnessBikeDefinition(
    connectedDevice: BleDevice(deviceId: 'trainer', name: 'Wahoo KICKR 1EB7'),
    connectedDeviceServices: trainerServices,
    data: ValueNotifier<String>(''),
    shouldAdvertiseZwift: true,
  );

  ZwiftEmulatorDefinition buildController() =>
      ZwiftEmulatorDefinition(device: BleDevice(deviceId: 'controller', name: 'BikeControl'));

  List<String> lower(List<String> uuids) => uuids.map((u) => u.toLowerCase()).toList();

  group('trainer endpoint', () {
    test('carries the Zwift Play service', () {
      expect(lower(buildFbd().serviceUUIDs), contains(zwiftPlay));
      expect(lower(buildFbd().advertiseServiceUUIDs), contains(zwiftPlay));
    });

    test('never carries the Ride service or the BikeControl marker', () {
      // Both belong to the controller endpoint only.
      final uuids = lower(buildFbd().serviceUUIDs);

      expect(uuids, isNot(contains(zwiftRide)));
      expect(uuids, isNot(contains(marker)));
      expect(lower(buildFbd().advertiseServiceUUIDs), isNot(contains(marker)));
    });

    test('keeps FTMS and the trainer passthrough', () {
      final uuids = lower(buildFbd().serviceUUIDs);

      expect(uuids, contains(FitnessBikeDefinition.FITNESS_MACHINE_SERVICE_UUID));
      expect(uuids, contains(deviceInformation));
    });
  });

  group('controller endpoint', () {
    test('is discoverable as a BikeControl controller', () {
      expect(lower(buildController().serviceUUIDs), contains(marker));
      expect(lower(buildController().advertiseServiceUUIDs), contains(marker));
    });

    test('carries the Ride service', () {
      expect(lower(buildController().serviceUUIDs), contains(zwiftRide));
    });

    test('the marker carries no characteristics and does not throw when walked', () {
      // Dispatch walks every service a definition claims.
      expect(buildController().getCharacteristics(marker), isEmpty);
    });
  });

  group('advertised name', () {
    late DirconEmulator emulator;

    setUp(() {
      emulator = DirconEmulator();
      emulator.deviceName = () => 'Wahoo KICKR 1EB7';
    });

    test('names the trainer after the device by default', () {
      emulator.composite.attach(buildFbd());

      expect(emulator.advertisementName, 'Wahoo KICKR 1EB7 - BikeControl');
    });

    test('an override replaces the name, keeping "BikeControl" off the wire', () {
      emulator.composite.attach(buildFbd());
      emulator.advertisementNameOverride = () => 'Zwift Hub';

      expect(emulator.advertisementName, 'Zwift Hub');
    });

    test('a null override leaves the default alone', () {
      emulator.composite.attach(buildFbd());
      emulator.advertisementNameOverride = () => null;

      expect(emulator.advertisementName, 'Wahoo KICKR 1EB7 - BikeControl');
    });

    test('the trial label rides on the overridden name', () {
      emulator.composite.attach(buildFbd());
      emulator.advertisementNameOverride = () => 'Zwift Hub';
      emulator.isTrial = () => true;

      expect(emulator.advertisementName, 'Zwift Hub - 20 min trial');
    });

    test('a standalone controller keeps its name through an override', () {
      emulator.composite.attach(buildController());
      emulator.advertisementNameOverride = () => 'Zwift Hub';

      expect(emulator.advertisementName, 'BikeControl');
    });
  });

  group('the name the bridge gives Rouvy', () {
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
  });
}
