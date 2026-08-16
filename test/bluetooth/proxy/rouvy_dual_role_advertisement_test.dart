import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prop/emulators/definitions/composite_ble_definition.dart';
import 'package:prop/emulators/definitions/fitness_bike_definition.dart';
import 'package:prop/emulators/definitions/zwift_emulator_definition.dart';
import 'package:prop/utils/constants.dart';
import 'package:universal_ble/universal_ble.dart';

/// The surface a trainer app sees when the bridge runs as both the trainer and
/// a controller. Rouvy is the strict one here: it takes a single Zwift custom
/// service per device and hangs on "Connecting" when offered two, and it only
/// grants the Remote Control role to a device carrying the BikeControl marker
/// service. Both are advertisement-shape rules, so they are asserted on the
/// definitions' service lists rather than over a live socket.
void main() {
  const zwiftPlay = FtmsMdnsConstants.ZWIFT_PLAY_SERVICE_UUID_LC;
  const zwiftRide = FtmsMdnsConstants.ZWIFT_RIDE_CUSTOM_SERVICE_UUID;
  const marker = FtmsMdnsConstants.BIKE_CONTROL_MARKER_SERVICE_UUID;
  const deviceInformation = '0000180a-0000-1000-8000-00805f9b34fb';

  final trainerServices = [
    BleService(FitnessBikeDefinition.FITNESS_MACHINE_SERVICE_UUID, []),
    BleService(deviceInformation, []),
    BleService('a026ee01-0a7d-4ab3-97fa-f1500f9feb8b', []),
  ];

  FitnessBikeDefinition buildFbd({required bool exposeZwiftPlayService}) => FitnessBikeDefinition(
    connectedDevice: BleDevice(deviceId: 'trainer', name: 'Wahoo KICKR 1EB7'),
    connectedDeviceServices: trainerServices,
    data: ValueNotifier<String>(''),
    shouldAdvertiseZwift: true,
    exposeZwiftPlayService: exposeZwiftPlayService,
  );

  ZwiftEmulatorDefinition buildController() =>
      ZwiftEmulatorDefinition(device: BleDevice(deviceId: 'controller', name: 'BikeControl'));

  List<String> lower(List<String> uuids) => uuids.map((u) => u.toLowerCase()).toList();

  group('FitnessBikeDefinition Zwift Play service', () {
    test('is offered by default so Zwift keeps the service it expects', () {
      final def = buildFbd(exposeZwiftPlayService: true);

      expect(lower(def.serviceUUIDs), contains(zwiftPlay));
      expect(lower(def.advertiseServiceUUIDs), contains(zwiftPlay));
    });

    test('is withheld when a sibling definition owns the Zwift Ride service', () {
      final def = buildFbd(exposeZwiftPlayService: false);

      expect(lower(def.serviceUUIDs), isNot(contains(zwiftPlay)));
      expect(lower(def.advertiseServiceUUIDs), isNot(contains(zwiftPlay)));
    });

    test('withholding it keeps FTMS and the trainer passthrough intact', () {
      // Regression guard: the passthrough shares a flag with the Zwift block,
      // and dropping Device Information leaves Rouvy waiting on the
      // manufacturer name forever — the same "stuck on Connecting" symptom the
      // Play service caused.
      final def = buildFbd(exposeZwiftPlayService: false);
      final uuids = lower(def.serviceUUIDs);

      expect(uuids, contains(FitnessBikeDefinition.FITNESS_MACHINE_SERVICE_UUID));
      expect(uuids, contains(deviceInformation));
      expect(uuids, contains('a026ee01-0a7d-4ab3-97fa-f1500f9feb8b'));
      expect(lower(def.advertiseServiceUUIDs), contains(FitnessBikeDefinition.FITNESS_MACHINE_SERVICE_UUID));
    });
  });

  group('ZwiftEmulatorDefinition BikeControl marker', () {
    test('is discoverable, which is what earns the Remote Control role', () {
      expect(lower(buildController().serviceUUIDs), contains(marker));
    });

    test('is advertised, which is what keeps the device in the filtered list', () {
      expect(lower(buildController().advertiseServiceUUIDs), contains(marker));
    });

    test('carries no characteristics and does not throw when walked', () {
      // Dispatch enumerates every service a definition claims, so a marker
      // without a backing entry would take down every write and subscribe.
      expect(buildController().getCharacteristics(marker), isEmpty);
    });

    test('does not displace the Zwift Ride service', () {
      expect(lower(buildController().serviceUUIDs), contains(zwiftRide));
    });
  });

  group('trainer + controller composite', () {
    late CompositeBleDefinition composite;

    setUp(() {
      composite = CompositeBleDefinition(
        initial: [buildFbd(exposeZwiftPlayService: false), buildController()],
      );
    });

    test('offers exactly one Zwift custom service', () {
      final zwiftServices = lower(
        composite.serviceUUIDs,
      ).where((u) => u == zwiftPlay || u == zwiftRide).toList();

      expect(zwiftServices, [zwiftRide]);
    });

    test('offers the trainer, the controller and the marker together', () {
      final uuids = lower(composite.serviceUUIDs);

      expect(uuids, contains(FitnessBikeDefinition.FITNESS_MACHINE_SERVICE_UUID));
      expect(uuids, contains(deviceInformation));
      expect(uuids, contains(zwiftRide));
      expect(uuids, contains(marker));
    });

    test('advertises the marker so both roles survive the device list', () {
      expect(lower(composite.advertiseServiceUUIDs), contains(marker));
    });

    test('routes a Zwift sync write with the marker service attached', () {
      // Exercises the owner walk across both children, marker included.
      expect(
        () => composite.onWriteRequest(
          FtmsMdnsConstants.ZWIFT_SYNC_RX_CHARACTERISTIC_UUID,
          FtmsMdnsConstants.RIDE_ON,
        ),
        returnsNormally,
      );
    });
  });
}
