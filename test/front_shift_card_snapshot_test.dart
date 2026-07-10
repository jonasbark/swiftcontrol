import 'package:bike_control/bluetooth/devices/proxy/proxy_device.dart';
import 'package:bike_control/models/shifting_config.dart';
import 'package:bike_control/pages/proxy_device_details/front_shift_card.dart';
import 'package:bike_control/utils/core.dart' show core;
import 'package:flutter_test/flutter_test.dart';
import 'package:prop/emulators/definitions/fitness_bike_definition.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:universal_ble/universal_ble.dart';

import 'widget_snapshot.dart';

/// Example: snapshotting [FrontShiftCard] in every locale with the generic
/// [captureWidget] harness. The only widget-specific code is the trainer/config
/// state the card reads — everything else (theme, l10n, fonts, capture) is the
/// harness. Run: `flutter test test/front_shift_card_snapshot_test.dart`
Future<void> main() async {
  await ensureSnapshotHarness();

  // A connected FTMS proxy trainer + its live fitness-bike definition, and an
  // active ShiftingConfig with front shift ON so the card renders expanded.
  final proxy =
      ProxyDevice(
          BleDevice(
            name: 'Smart Trainer',
            deviceId: '00:11:22:33:44:55',
            services: [FitnessBikeDefinition.FITNESS_MACHINE_SERVICE_UUID],
          ),
        )
        ..services = [
          BleService(FitnessBikeDefinition.FITNESS_MACHINE_SERVICE_UUID, []),
        ]
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

  testWidgets('FrontShiftCard → PNG per locale', (tester) async {
    await captureWidget(
      tester,
      name: 'front_shift_card',
      width: 380,
      locales: const ['en', 'de', 'es', 'fr', 'it', 'pl'],
      builder: (context) =>
          FrontShiftCard(device: proxy, definition: definition),
    );
  });
}
