// The same physical trainer is regularly discovered twice — once over BLE and
// once over mDNS/DirCon — and the two entries used to be indistinguishable:
// same name, same "Supports virtual shifting" subtitle, same bike icon. These
// tests pin the four places that now name the upstream transport.
import 'package:bike_control/bluetooth/devices/proxy/proxy_device.dart';
import 'package:bike_control/gen/l10n.dart';
import 'package:bike_control/pages/home/home_page.dart';
import 'package:bike_control/pages/onboarding/steps/step_trainer.dart';
import 'package:bike_control/services/trainer_self_test/self_test_result.dart';
import 'package:bike_control/utils/actions/base_actions.dart';
import 'package:bike_control/utils/core.dart';
import 'package:bike_control/utils/keymap/apps/supported_app.dart';
import 'package:bike_control/widgets/menu.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prop/emulators/definitions/fitness_bike_definition.dart';
import 'package:prop/emulators/dircon_emulator.dart' show RetrofitMode;
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:universal_ble/universal_ble.dart';

Future<void> main() async {
  await AppLocalizations.load(const Locale('en'));

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    core.settings.prefs = await SharedPreferences.getInstance();
    core.actionHandler = StubActions();
    core.connection.devices.clear();
  });

  tearDown(() => core.connection.devices.clear());

  BleDevice scan(String id, {String name = 'KICKR CORE 1EB7'}) => BleDevice(
    deviceId: id,
    name: name,
    services: const [FitnessBikeDefinition.FITNESS_MACHINE_SERVICE_UUID],
  );

  ProxyDevice bleTrainer({String id = 'AA:BB:CC:DD:EE:FF'}) => ProxyDevice(scan(id));

  ProxyDevice wifiTrainer({String id = 'dircon://KICKR CORE 1EB7'}) =>
      ProxyDevice.wifi(scan(id), host: '192.168.1.20', port: 36866);

  // Mirrors reveal_overlay_section_test.dart's makeVsDevice(): a trainer with
  // an attached (unprobed) FitnessBikeDefinition, which is what makes the
  // proto=/vsMode=/ftms= diagnostics fields appear in describeProxyDevice at
  // all. Named 'KICKR CORE' by default so device.trainerKey lines up with the
  // 'self_test_KICKR CORE' settings key the self-test group below seeds.
  ProxyDevice trainerWithFitnessBike({String id = 'kickr', String name = 'KICKR CORE'}) {
    final device = ProxyDevice(scan(id, name: name))
      ..services = [BleService(FitnessBikeDefinition.FITNESS_MACHINE_SERVICE_UUID, [])];
    device.debugAttachFitnessBike(
      FitnessBikeDefinition(
        connectedDevice: device.scanResult,
        connectedDeviceServices: device.services!,
        data: ValueNotifier(''),
      ),
    );
    return device;
  }

  Future<void> pump(WidgetTester tester, Widget Function(BuildContext) builder) async {
    await tester.pumpWidget(
      ShadcnApp(
        localizationsDelegates: const [AppLocalizations.delegate],
        supportedLocales: AppLocalizations.delegate.supportedLocales,
        home: Scaffold(child: SizedBox(width: 380, child: Builder(builder: builder))),
      ),
    );
    await tester.pump();
  }

  group('trainer picker names its transport', () {
    // The stage and the radar animate forever, so pump() — never
    // pumpAndSettle() — is the only way through these builds.
    Future<void> pumpPicker(WidgetTester tester, List<ProxyDevice> trainers) => pump(
      tester,
      (c) => SingleChildScrollView(
        child: onboardingTrainerBody(
          c,
          app: SupportedApp.supportedApps.first,
          trainers: trainers,
          onPick: (_) {},
        ),
      ),
    );

    testWidgets('a WiFi trainer reads "WiFi · Supports virtual shifting"', (tester) async {
      await pumpPicker(tester, [wifiTrainer()]);

      expect(find.text('WiFi · Supports virtual shifting'), findsOneWidget);
      expect(find.text('Bluetooth · Supports virtual shifting'), findsNothing);
      // …and the bare meta line, which both duplicates used to show, is gone.
      expect(find.text('Supports virtual shifting'), findsNothing);
    });

    testWidgets('a Bluetooth trainer reads "Bluetooth · Supports virtual shifting"', (tester) async {
      await pumpPicker(tester, [bleTrainer()]);

      expect(find.text('Bluetooth · Supports virtual shifting'), findsOneWidget);
      expect(find.text('WiFi · Supports virtual shifting'), findsNothing);
    });

    testWidgets('two entries for one trainer are told apart by subtitle and icon', (tester) async {
      await pumpPicker(tester, [bleTrainer(), wifiTrainer()]);

      // Same name twice — that is the support case — but two distinct rows.
      expect(find.text('KICKR CORE 1EB7'), findsNWidgets(2));
      expect(find.text('WiFi · Supports virtual shifting'), findsOneWidget);
      expect(find.text('Bluetooth · Supports virtual shifting'), findsOneWidget);

      // The leading mark carries the transport too; the generic bike icon that
      // said nothing about either row is no longer used for trainers.
      expect(find.byIcon(LucideIcons.bike), findsNothing);
      expect(find.byIcon(LucideIcons.wifi), findsOneWidget);
      // One in each row's leading slot… plus the scan card's own radar mark.
      expect(find.byIcon(LucideIcons.bluetooth), findsNWidgets(2));
    });

    testWidgets('the connected variant names the transport as well', (tester) async {
      final trainer = wifiTrainer()..debugSetTrainerAppConnected(true);
      expect(trainer.isBridged, isTrue);

      await pumpPicker(tester, [trainer]);

      expect(find.text('WiFi · Supports virtual shifting'), findsOneWidget);
      expect(find.byIcon(LucideIcons.wifi), findsOneWidget);
      expect(find.byIcon(LucideIcons.bike), findsNothing);
    });

    testWidgets('picker icons come straight from the helper', (tester) async {
      expect(onboardingTrainerIcon(wifiTrainer()), LucideIcons.wifi);
      expect(onboardingTrainerIcon(bleTrainer()), LucideIcons.bluetooth);
    });
  });

  group('nameBadge', () {
    Future<Widget?> badgeOf(WidgetTester tester, ProxyDevice device) async {
      Widget? badge;
      await pump(tester, (c) {
        badge = device.nameBadge(c);
        return badge ?? const SizedBox.shrink();
      });
      return badge;
    }

    testWidgets('a lone WiFi trainer still gets a WiFi badge', (tester) async {
      // No duplicate registered anywhere — the old exact-name gate returned
      // null here, which is precisely the case support kept hitting: the two
      // entries differ slightly (BLE advertisement vs DirCon service name).
      final badge = await badgeOf(tester, wifiTrainer());
      expect(badge, isA<Icon>());
      expect((badge as Icon).icon, LucideIcons.wifi);
    });

    testWidgets('a lone BLE trainer gets a Bluetooth badge', (tester) async {
      final badge = await badgeOf(tester, bleTrainer());
      expect((badge as Icon?)?.icon, LucideIcons.bluetooth);
    });

    testWidgets('non-trainers stay unbadged', (tester) async {
      final hrStrap = ProxyDevice(BleDevice(
        deviceId: 'hr',
        name: 'TICKR',
        services: const [FitnessBikeDefinition.HEART_RATE_MEASUREMENT_UUID],
      ));
      expect(hrStrap.isSmartTrainer, isFalse);
      expect(await badgeOf(tester, hrStrap), isNull);
    });
  });

  group('diagnostics bundle', () {
    test('records the upstream transport next to the downstream mode', () {
      expect(describeProxyDevice(wifiTrainer()), contains('upstream=wifi'));
      expect(describeProxyDevice(bleTrainer()), contains('upstream=ble'));
    });

    test('upstream is not the retrofit mode', () {
      // A BLE-discovered trainer bridged in wifi retrofit mode: `mode=` and
      // `upstream=` disagree on purpose, and that is the whole point of the
      // new field.
      final device = bleTrainer();
      device.setRetrofitMode(RetrofitMode.wifi);
      final line = describeProxyDevice(device);
      expect(line, contains('upstream=ble'));
      expect(line, contains('mode=wifi'));
    });

    test('trainer line carries proto, vsMode, ftms capability and selfTest', () async {
      SharedPreferences.setMockInitialValues({
        'self_test_KICKR CORE': SelfTestResult(
          at: DateTime(2026, 8, 20),
          verdict: SelfTestVerdict.pass,
          ergStepsPassed: 3,
          ergStepsTotal: 3,
          shiftStepsPassed: 3,
          shiftStepsTotal: 3,
          vsMode: 'targetPower',
          protocol: 'ftms',
        ).toJsonString(),
      });
      core.settings.prefs = await SharedPreferences.getInstance();

      final device = trainerWithFitnessBike();

      final line = describeProxyDevice(device);
      expect(line, contains('proto=ftms'));
      expect(line, contains('vsMode=targetPower'));
      expect(line, contains('ftms=unknown')); // unprobed definition
      expect(line, contains('selfTest=PASS,2026-08-20,a:3/3,b:3/3,targetPower'));
      expect(line, isNot(contains('lastCtl='))); // no control write happened
    });
  });

  group('describeControllers', () {
    test('renders firmware when known, plain toString otherwise', () {
      final withFw = bleTrainer(id: 'ctrl-with-fw')..firmwareVersion = '1.5.0';
      final withoutFw = bleTrainer(id: 'ctrl-without-fw');

      final s = describeControllers([withFw, withoutFw]);

      expect(s, contains('(fw 1.5.0)'));
      expect(s.split(', ').last, isNot(contains('fw')));
    });
  });

  group('chain card picks the live trainer', () {
    test('a bridged duplicate beats an idle one whatever the discovery order', () {
      final idle = wifiTrainer();
      final live = bleTrainer()..debugSetTrainerAppConnected(true);
      core.connection.devices.addAll([idle, live]);

      expect(chainProxy(), same(live));
    });

    test('a connected duplicate beats a merely discovered one', () {
      final discovered = wifiTrainer();
      final connected = bleTrainer()..isConnected = true;
      core.connection.devices.addAll([discovered, connected]);

      expect(chainProxy(), same(connected));
    });

    test('a connecting duplicate beats an idle one', () {
      final idle = wifiTrainer();
      final starting = bleTrainer()..isStarting.value = true;
      core.connection.devices.addAll([idle, starting]);

      expect(chainProxy(), same(starting));
    });

    test('rank order: bridged < connected < starting < idle', () {
      expect(proxyChainRank(bleTrainer()..debugSetTrainerAppConnected(true)), 0);
      expect(proxyChainRank(bleTrainer()..isConnected = true), 1);
      expect(proxyChainRank(bleTrainer()..isStarting.value = true), 2);
      expect(proxyChainRank(bleTrainer()), 3);
    });
  });
}
