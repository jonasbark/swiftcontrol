@Tags(['screenshots'])
library;

import 'package:bike_control/bluetooth/devices/proxy/proxy_device.dart';
import 'package:bike_control/gen/l10n.dart';
import 'package:bike_control/models/shifting_config.dart';
import 'package:bike_control/pages/proxy_device_details/gear_hero_card.dart';
import 'package:bike_control/utils/core.dart' show core;
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_screenshot/golden_screenshot.dart';
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

  final definition =
      FitnessBikeDefinition(
          connectedDevice: proxy.scanResult,
          connectedDeviceServices: proxy.services!,
          data: ValueNotifier(''),
        )
        ..setDebugValues()
        ..setFrontShiftEnabled(true);

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
      builder: (context) => GearHeroCard(definition: definition, onEditSettings: () {}),
    );
    await captureWidget(
      tester,
      name: 'gear_hero_drivetrain_dark',
      width: 380,
      brightness: Brightness.dark,
      builder: (context) => GearHeroCard(definition: definition, onEditSettings: () {}),
    );
  });

  /// Under the plain test binding every glyph is a uniform Ahem box, so a
  /// column that drifts because Geist's "1" is narrower than its "2" measures
  /// as perfectly still. This one runs on the real font, which is the only
  /// place that drift is visible.
  testWidgets('the shift column holds its place across every gear', (tester) async {
    definition.setMaxGear(24);
    await tester.pumpWidget(
      ShadcnApp(
        debugShowCheckedModeBanner: false,
        localizationsDelegates: const [AppLocalizations.delegate],
        supportedLocales: AppLocalizations.delegate.supportedLocales,
        home: Scaffold(
          child: SizedBox(width: 380, child: GearHeroCard(definition: definition)),
        ),
      ),
    );
    await tester.pump();
    await tester.loadAssets();
    await tester.pump();

    Offset? minus;
    Offset? plus;
    for (var gear = 1; gear <= 24; gear++) {
      definition.setTargetGear(gear);
      await tester.pump();
      final atMinus = tester.getCenter(find.byIcon(LucideIcons.minus));
      final atPlus = tester.getCenter(find.byIcon(LucideIcons.plus));
      minus ??= atMinus;
      plus ??= atPlus;
      // Not "close enough": a button that moves at all moves under a thumb
      // already on its way down, and the rider gets the gear they didn't ask for.
      expect(atMinus, minus, reason: 'shift-down moved on gear $gear');
      expect(atPlus, plus, reason: 'shift-up moved on gear $gear');
    }
    await tester.pump(const Duration(milliseconds: 600));
  });
}
