@Tags(['screenshots'])
library;

import 'package:bike_control/bluetooth/devices/proxy/proxy_device.dart';
import 'package:bike_control/pages/home/chain_state.dart';
import 'package:bike_control/widgets/drivetrain/drivetrain_controls.dart';
import 'package:bike_control/widgets/home/chain_card.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prop/emulators/definitions/fitness_bike_definition.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:universal_ble/universal_ble.dart';

import 'widget_snapshot.dart';

/// The home screen's trainer link with the drivetrain in its body — the front
/// page's live picture of what shifting is doing. Run:
/// `flutter test --run-skipped test/trainer_chain_card_drivetrain_snapshot_test.dart`
Future<void> main() async {
  await ensureSnapshotHarness();

  final proxy =
      ProxyDevice(
          BleDevice(
            name: 'KICKR CORE',
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
  )
    ..setDebugValues()
    ..setMaxGear(24)
    ..setFrontShiftEnabled(true);

  const link = ChainLink(
    key: ChainLinkKey.trainer,
    id: 'trainer',
    status: LinkStatus.ready,
    title: 'KICKR CORE',
    steps: [],
    optional: true,
  );

  Widget card({required bool dim}) => ChainCard(
    link: link,
    tile: const Icon(LucideIcons.bike, size: 22),
    title: 'KICKR CORE',
    statusLabel: dim ? 'Connected' : 'Bridged to MyWhoosh',
    editLabel: 'Edit',
    onEdit: () {},
    onTap: () {},
    body: DrivetrainControls(definition: definition, compact: true, dim: dim),
  );

  testWidgets('trainer chain card with drivetrain → PNG', (tester) async {
    await captureWidget(
      tester,
      name: 'trainer_chain_card_drivetrain',
      width: 380,
      builder: (context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [card(dim: false), const Gap(12), card(dim: true)],
      ),
    );
    await captureWidget(
      tester,
      name: 'trainer_chain_card_drivetrain_dark',
      width: 380,
      brightness: Brightness.dark,
      builder: (context) => card(dim: false),
    );
  });
}
