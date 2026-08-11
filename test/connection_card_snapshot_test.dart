@Tags(['screenshots'])
library;

import 'package:bike_control/bluetooth/devices/proxy/proxy_device.dart';
import 'package:bike_control/pages/proxy_device_details/connection_card.dart';
import 'package:bike_control/utils/core.dart' show core;
import 'package:bike_control/utils/requirements/multi.dart' show Target;
import 'package:flutter_test/flutter_test.dart';
import 'package:prop/emulators/definitions/fitness_bike_definition.dart';
import 'package:universal_ble/universal_ble.dart';

import 'widget_snapshot.dart';

/// Snapshots the [ConnectionCard] mode picker for the blog post
/// "Virtual Shifting with BikeControl — and Without": a disconnected FTMS
/// trainer, so the accordion starts expanded and all three rows are visible,
/// including "No connection → Let MyWhoosh handle virtual shifting".
///
/// Run: `flutter test --run-skipped test/connection_card_snapshot_test.dart`
Future<void> main() async {
  await ensureSnapshotHarness();

  // MyWhoosh as the selected trainer app so the "No connection" row renders the
  // personalized "Let MyWhoosh handle virtual shifting, if supported" subtitle.
  await core.settings.prefs.setString('trainer_app', 'MyWhoosh');
  // Target.otherDevice always has a usable transport, so the Virtual Shifting
  // row shows its real hint instead of the "enable a Trainer Connection" nag.
  await core.settings.setLastTarget(Target.otherDevice);

  // A disconnected FTMS smart trainer: initState leaves the picker expanded.
  final trainer = ProxyDevice(
    BleDevice(
      deviceId: '00:11:22:33:44:55',
      name: 'KICKR CORE',
      services: const [FitnessBikeDefinition.FITNESS_MACHINE_SERVICE_UUID],
    ),
  );

  testWidgets('ConnectionCard mode picker → PNG', (tester) async {
    await captureWidget(
      tester,
      name: 'connection_card',
      width: 400,
      locales: const ['en'],
      builder: (context) => ConnectionCard(device: trainer),
    );
  });
}
