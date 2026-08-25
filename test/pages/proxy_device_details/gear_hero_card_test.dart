import 'package:bike_control/bluetooth/devices/proxy/proxy_device.dart';
import 'package:bike_control/gen/l10n.dart';
import 'package:bike_control/pages/proxy_device_details/gear_hero_card.dart';
import 'package:bike_control/utils/actions/base_actions.dart';
import 'package:bike_control/utils/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prop/emulators/definitions/fitness_bike_definition.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:universal_ble/universal_ble.dart';

/// The surface a rider looks at while shifting: the number has to stay put
/// under the buttons, and the front derailleur has to be reachable from here.
Future<void> main() async {
  await AppLocalizations.load(const Locale('en'));

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    core.settings.prefs = await SharedPreferences.getInstance();
    core.actionHandler = StubActions();
  });

  FitnessBikeDefinition makeDefinition() {
    final device = ProxyDevice(
      BleDevice(
        deviceId: 'kickr',
        name: 'KICKR CORE',
        services: const [FitnessBikeDefinition.FITNESS_MACHINE_SERVICE_UUID],
      ),
    )..services = [BleService(FitnessBikeDefinition.FITNESS_MACHINE_SERVICE_UUID, [])];
    return FitnessBikeDefinition(
      connectedDevice: device.scanResult,
      connectedDeviceServices: device.services!,
      data: ValueNotifier(''),
    );
  }

  Future<void> show(WidgetTester tester, FitnessBikeDefinition def, {VoidCallback? onEditSettings}) async {
    await tester.pumpWidget(
      ShadcnApp(
        localizationsDelegates: const [AppLocalizations.delegate],
        supportedLocales: AppLocalizations.delegate.supportedLocales,
        home: Scaffold(
          child: SizedBox(
            width: 380,
            child: GearHeroCard(definition: def, onEditSettings: onEditSettings),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  /// A shift kicks off the FTMS control-point handshake, which parks a 400 ms
  /// timer the test binding refuses to end on. Nothing here waits on it — this
  /// just lets it run out.
  Future<void> drainHandshake(WidgetTester tester) => tester.pump(const Duration(milliseconds: 500));

  testWidgets('the shift buttons hold their place from 9 to 12', (tester) async {
    final def = makeDefinition()..setMaxGear(24);

    def.setTargetGear(9);
    await show(tester, def);
    final minusAtNine = tester.getCenter(find.byIcon(LucideIcons.minus));
    final plusAtNine = tester.getCenter(find.byIcon(LucideIcons.plus));

    def.setTargetGear(12);
    await tester.pump();
    // A two-digit gear must not shove the buttons outwards — a target that
    // moves under a thumb already on its way down is a mis-shift.
    expect(tester.getCenter(find.byIcon(LucideIcons.minus)), minusAtNine);
    expect(tester.getCenter(find.byIcon(LucideIcons.plus)), plusAtNine);
    await drainHandshake(tester);
  });

  testWidgets('the box is sized for the highest gear, not the value on screen', (tester) async {
    // The reservation is a hidden digit string the size of the highest gear —
    // asserting on it says what the layout guarantees, rather than inferring it
    // from where the buttons happened to land.
    final wide = makeDefinition()..setMaxGear(24);
    wide.setTargetGear(9);
    await show(tester, wide);
    expect(find.text('00'), findsOneWidget);
    expect(find.text('0'), findsNothing);
    await drainHandshake(tester);

    final narrow = makeDefinition()..setMaxGear(9);
    narrow.setTargetGear(9);
    await show(tester, narrow);
    expect(find.text('0'), findsOneWidget);
    await drainHandshake(tester);
  });

  group('front derailleur', () {
    testWidgets('is absent until front shifting is on', (tester) async {
      final def = makeDefinition()..setMaxGear(24);
      await show(tester, def);
      expect(find.byIcon(LucideIcons.repeat), findsNothing);
    });

    testWidgets('switches the chainring from this card', (tester) async {
      final def = makeDefinition()
        ..setMaxGear(24)
        ..setChainringTeeth(34, 50)
        ..setFrontShiftEnabled(true);
      await show(tester, def);

      expect(find.text('1× · 34T'), findsOneWidget);
      await tester.tap(find.byIcon(LucideIcons.repeat));
      await tester.pump();

      expect(def.frontRing.value, FrontRing.large);
      expect(find.text('2× · 50T'), findsOneWidget);
      await drainHandshake(tester);
    });
  });

  testWidgets('Edit is offered only when there are settings to open', (tester) async {
    final def = makeDefinition()..setMaxGear(24);

    await show(tester, def);
    expect(find.text('Edit'), findsNothing);

    var opened = 0;
    await show(tester, def, onEditSettings: () => opened++);
    await tester.tap(find.text('Edit'));
    await tester.pump();
    expect(opened, 1);
  });
}
