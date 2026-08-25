@Tags(['screenshots'])
library;

import 'package:bike_control/bluetooth/devices/proxy/proxy_device.dart';
import 'package:bike_control/models/shifting_config.dart';
import 'package:bike_control/pages/proxy_device_details/gear_hero_card.dart';
import 'package:bike_control/utils/core.dart' show core;
import 'package:flutter_test/flutter_test.dart';
import 'package:prop/emulators/definitions/fitness_bike_definition.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:universal_ble/universal_ble.dart';

import 'widget_snapshot.dart';

/// The gear hero with the drivetrain above the number, which is the whole
/// surface a rider watches while shifting. Run:
/// `flutter test --run-skipped test/gear_hero_drivetrain_snapshot_test.dart`
Future<void> main() async {
  await ensureSnapshotHarness();

  final proxy =
      ProxyDevice(
          BleDevice(
            name: 'Smart Trainer',
            deviceId: '00:11:22:33:44:55',
            services: [FitnessBikeDefinition.FITNESS_MACHINE_SERVICE_UUID],
          ),
        )
        ..services = [BleService(FitnessBikeDefinition.FITNESS_MACHINE_SERVICE_UUID, [])]
        ..isConnected = true;

  final definition = FitnessBikeDefinition(
    connectedDevice: proxy.scanResult,
    connectedDeviceServices: proxy.services!,
    data: ValueNotifier(''),
  )..setDebugValues();

  await core.shiftingConfigs.upsert(
    ShiftingConfig.defaults(trainerKey: proxy.trainerKey).copyWith(
      frontShiftEnabled: true,
      smallChainringTeeth: 34,
      largeChainringTeeth: 50,
    ),
  );

  testWidgets('GearHeroCard with the drivetrain → PNG', (tester) async {
    await captureWidget(
      tester,
      name: 'gear_hero_drivetrain',
      width: 380,
      builder: (context) => GearHeroCard(definition: definition, simOnly: true),
    );
    await captureWidget(
      tester,
      name: 'gear_hero_drivetrain_dark',
      width: 380,
      brightness: Brightness.dark,
      builder: (context) => GearHeroCard(definition: definition, simOnly: true),
    );
  });
}
