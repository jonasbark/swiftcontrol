import 'package:bike_control/gen/l10n.dart';
import 'package:bike_control/pages/sensors/sensor_quantity_selector.dart';
import 'package:bike_control/pages/sensors/sensors_section.dart';
import 'package:bike_control/services/sensors/fake_sensor_source.dart';
import 'package:bike_control/services/sensors/sensor_hub.dart';
import 'package:bike_control/services/sensors/sensor_quantity.dart';
import 'package:bike_control/utils/core.dart';
import 'package:bike_control/utils/iap/iap_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // The page's Pro badge reaches IAPManager, which reaches Supabase.instance;
  // give it an offline dummy instance (no session, so no request is made).
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'http://127.0.0.1:9',
      anonKey: 'sensors-section-test-anon-key',
      debug: false,
      authOptions: const FlutterAuthClientOptions(
        localStorage: EmptyLocalStorage(),
        detectSessionInUri: false,
        autoRefreshToken: false,
      ),
    );
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    core.settings.prefs = await SharedPreferences.getInstance();
    // Deterministic regardless of test order/leakage from other files in the
    // same run: every test starts NOT Pro unless it opts in explicitly.
    IAPManager.instance.setProForTesting(enabled: false);
  });

  Future<SensorHub> pumpSection(WidgetTester tester) async {
    final hub = SensorHub();
    hub.register(FakeSensorSource(
      id: 'strap',
      displayName: 'TICKR 1234',
      provides: {SensorQuantity.heartRate},
    ));
    await tester.pumpWidget(
      ShadcnApp(
        localizationsDelegates: [
          ...ShadcnLocalizations.localizationsDelegates,
          AppLocalizations.delegate,
        ],
        supportedLocales: const [Locale('en')],
        // A bare ShadcnApp gives the Select popup nowhere to mount (shadcn's
        // popover/drawer overlay lives on Scaffold) — production always hosts
        // this section inside one (ProxyDeviceDetailsPage, SensorsPage), so
        // mirror that here rather than only in production.
        home: Scaffold(child: SensorsSection(hub: hub)),
      ),
    );
    await tester.pumpAndSettle();
    return hub;
  }

  testWidgets('lists a registered source by display name', (tester) async {
    await pumpSection(tester);

    expect(find.text('TICKR 1234'), findsOneWidget);
  });

  testWidgets('a quantity with no selection resolves to the trainer', (tester) async {
    final hub = await pumpSection(tester);

    expect(hub.selectionFor(SensorQuantity.heartRate), isNull);
  });

  testWidgets('selecting a source updates the hub', (tester) async {
    final hub = await pumpSection(tester);

    hub.select(SensorQuantity.heartRate, 'strap');
    await tester.pumpAndSettle();

    expect(hub.selectionFor(SensorQuantity.heartRate), 'strap');
    expect(find.byType(SensorsSection), findsOneWidget);
  });

  // V2 (wave 3): `SensorHub.persistSelections` existed and was fully unit
  // tested, but nothing in production ever called it — `_handleChanged`
  // updated the hub in memory and stopped, so the persisted key never
  // existed and a rider's choice never survived an app restart. This drives
  // the actual rider-facing widget, not the hub directly, so it fails unless
  // `_handleChanged` itself persists.
  group('persistence', () {
    testWidgets('picking a source through the selector persists it', (tester) async {
      IAPManager.instance.setProForTesting(enabled: true);
      addTearDown(() => IAPManager.instance.setProForTesting(enabled: false));
      await pumpSection(tester);

      await tester.tap(find.descendant(
          of: find.byKey(const Key('sensor-quantity-heartRate')),
          matching: find.byType(Select<String?>),
        ));
      await tester.pumpAndSettle();
      // The closed select also renders the placeholder "Trainer" text, so the
      // paired source's name only ever matches once — in the popup.
      await tester.tap(find.text('TICKR 1234').last);
      await tester.pumpAndSettle();

      expect(core.settings.getSensorSelection(SensorQuantity.heartRate.name), 'strap');
    });

    testWidgets('picking "Trainer" again persists the selection back to null', (tester) async {
      IAPManager.instance.setProForTesting(enabled: true);
      addTearDown(() => IAPManager.instance.setProForTesting(enabled: false));
      final hub = await pumpSection(tester);
      hub.select(SensorQuantity.heartRate, 'strap');
      await core.settings.setSensorSelection(SensorQuantity.heartRate.name, 'strap');
      await tester.pumpAndSettle();

      await tester.tap(find.descendant(
          of: find.byKey(const Key('sensor-quantity-heartRate')),
          matching: find.byType(Select<String?>),
        ));
      await tester.pumpAndSettle();
      await tester.tap(find.text(AppLocalizations.current.sensorSourceTrainer).last);
      await tester.pumpAndSettle();

      expect(core.settings.getSensorSelection(SensorQuantity.heartRate.name), isNull);
    });

    // The exact ordering wave 1 made possible and wave 3 must not break: a
    // rider can open this page while a previously-picked strap has not
    // registered yet (still cold-starting, or just out of range). Changing
    // the selection here persists every quantity's CURRENT selection (see
    // `SensorHub.persistSelections`), so this proves that sweep cannot wipe
    // a different quantity's pending id just because its source isn't live.
    testWidgets(
      'persisting a change does not erase a different quantity\'s still-pending selection',
      (tester) async {
        await core.settings.setSensorSelection(SensorQuantity.power.name, 'pending-power-strap');
        final hub = SensorHub();
        hub.loadSelections(core.settings);
        hub.register(FakeSensorSource(
          id: 'strap',
          displayName: 'TICKR 1234',
          provides: {SensorQuantity.heartRate},
        ));
        IAPManager.instance.setProForTesting(enabled: true);
        addTearDown(() => IAPManager.instance.setProForTesting(enabled: false));

        await tester.pumpWidget(
          ShadcnApp(
            localizationsDelegates: [
              ...ShadcnLocalizations.localizationsDelegates,
              AppLocalizations.delegate,
            ],
            supportedLocales: const [Locale('en')],
            home: Scaffold(child: SensorsSection(hub: hub)),
          ),
        );
        await tester.pumpAndSettle();

        // Change the ONLY quantity this section exposes — heart rate — while
        // `power`'s selection above is still pending (its source, if it ever
        // registers, is not part of this test at all).
        await tester.tap(find.descendant(
          of: find.byKey(const Key('sensor-quantity-heartRate')),
          matching: find.byType(Select<String?>),
        ));
        await tester.pumpAndSettle();
        await tester.tap(find.text('TICKR 1234').last);
        await tester.pumpAndSettle();

        expect(core.settings.getSensorSelection(SensorQuantity.heartRate.name), 'strap');
        expect(core.settings.getSensorSelection(SensorQuantity.power.name), 'pending-power-strap');
      },
    );
  });

  testWidgets('a dropped-out source surfaces the fallback indicator', (tester) async {
    var clock = DateTime.utc(2026, 9, 4, 12);
    final hub = SensorHub(now: () => clock);
    final source = FakeSensorSource(
      id: 'strap',
      displayName: 'TICKR 1234',
      provides: {SensorQuantity.heartRate},
    );
    hub.register(source);
    hub.select(SensorQuantity.heartRate, 'strap');
    source.emit(SensorQuantity.heartRate, 150, at: clock);

    await tester.pumpWidget(
      ShadcnApp(
        localizationsDelegates: [
          ...ShadcnLocalizations.localizationsDelegates,
          AppLocalizations.delegate,
        ],
        supportedLocales: const [Locale('en')],
        home: SensorsSection(hub: hub),
      ),
    );
    await tester.pumpAndSettle();

    clock = clock.add(const Duration(seconds: 6));
    hub.tick();
    await tester.pumpAndSettle();

    expect(hub.droppedOut(SensorQuantity.heartRate).value, isTrue);
    expect(find.byKey(const Key('sensor-dropout-heartRate')), findsOneWidget);
  });

  // The known issue carried in from Task 3: selecting a source that has never
  // produced a reading sets `droppedOut` to true immediately, because the hub
  // treats "no reading" as stale. Left unhandled, the UI would flash the same
  // "signal lost" indicator the instant a rider picks a strap, before its
  // first notification ever arrives. This proves the UI distinguishes that
  // from a real drop-out instead of conflating the two.
  group('a source selected before its first reading arrives', () {
    testWidgets('the hub already reports it as dropped out (the known caveat)', (tester) async {
      final hub = SensorHub();
      hub.register(FakeSensorSource(
        id: 'strap',
        displayName: 'TICKR 1234',
        provides: {SensorQuantity.heartRate},
      ));

      hub.select(SensorQuantity.heartRate, 'strap');

      expect(hub.droppedOut(SensorQuantity.heartRate).value, isTrue);
    });

    testWidgets('the UI shows a waiting state, not the drop-out indicator', (tester) async {
      final hub = SensorHub();
      hub.register(FakeSensorSource(
        id: 'strap',
        displayName: 'TICKR 1234',
        provides: {SensorQuantity.heartRate},
      ));
      hub.select(SensorQuantity.heartRate, 'strap');

      await tester.pumpWidget(
        ShadcnApp(
          localizationsDelegates: [
            ...ShadcnLocalizations.localizationsDelegates,
            AppLocalizations.delegate,
          ],
          supportedLocales: const [Locale('en')],
          home: SensorsSection(hub: hub),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('sensor-waiting-heartRate')), findsOneWidget);
      expect(find.byKey(const Key('sensor-dropout-heartRate')), findsNothing);
    });

    testWidgets('the waiting state clears once the first reading lands', (tester) async {
      var clock = DateTime.utc(2026, 9, 4, 12);
      final hub = SensorHub(now: () => clock);
      final source = FakeSensorSource(
        id: 'strap',
        displayName: 'TICKR 1234',
        provides: {SensorQuantity.heartRate},
      );
      hub.register(source);
      hub.select(SensorQuantity.heartRate, 'strap');

      await tester.pumpWidget(
        ShadcnApp(
          localizationsDelegates: [
            ...ShadcnLocalizations.localizationsDelegates,
            AppLocalizations.delegate,
          ],
          supportedLocales: const [Locale('en')],
          home: SensorsSection(hub: hub),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('sensor-waiting-heartRate')), findsOneWidget);

      source.emit(SensorQuantity.heartRate, 150, at: clock);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('sensor-waiting-heartRate')), findsNothing);
      expect(find.byKey(const Key('sensor-dropout-heartRate')), findsNothing);
    });
  });

  // Pro gate: consistent with Bridge/Virtual Shifting, external sensor
  // selection is a Pro feature via isProEnabledForCurrentDevice specifically
  // (the OrDidPurchaseOld grandfather must not apply here).
  group('Pro gate', () {
    testWidgets('flags the heart rate selector as Pro-gated when not Pro', (tester) async {
      await pumpSection(tester);

      expect(find.byKey(const Key('sensor-pro-badge-heartRate')), findsOneWidget);
    });

    testWidgets('drops the Pro badge once the device is Pro', (tester) async {
      IAPManager.instance.setProForTesting(enabled: true);
      addTearDown(() => IAPManager.instance.setProForTesting(enabled: false));

      await pumpSection(tester);

      expect(find.byKey(const Key('sensor-pro-badge-heartRate')), findsNothing);
    });
  });

  // T5-C: cadence and power get their own rows alongside heart rate. Speed
  // stays hidden — there is still no speed source to resolve to. Keyed
  // lookups only, never literal translated text (see the plan's Task 5
  // checklist).
  group('cadence and power rows', () {
    testWidgets('renders a row for heart rate, cadence and power, but not speed', (tester) async {
      await pumpSection(tester);

      expect(find.byKey(const Key('sensor-quantity-heartRate')), findsOneWidget);
      expect(find.byKey(const Key('sensor-quantity-cadence')), findsOneWidget);
      expect(find.byKey(const Key('sensor-quantity-power')), findsOneWidget);
      expect(find.byKey(const Key('sensor-quantity-speed')), findsNothing);
      expect(find.byType(SensorQuantitySelector), findsNWidgets(3));
    });

    testWidgets('selecting a cadence source updates the hub', (tester) async {
      final hub = SensorHub();
      hub.register(FakeSensorSource(
        id: 'cad-1',
        displayName: 'Cadence sensor',
        provides: {SensorQuantity.cadence},
      ));
      await tester.pumpWidget(
        ShadcnApp(
          localizationsDelegates: [
            ...ShadcnLocalizations.localizationsDelegates,
            AppLocalizations.delegate,
          ],
          supportedLocales: const [Locale('en')],
          home: Scaffold(child: SensorsSection(hub: hub)),
        ),
      );
      await tester.pumpAndSettle();

      hub.select(SensorQuantity.cadence, 'cad-1');
      await tester.pumpAndSettle();

      expect(hub.selectionFor(SensorQuantity.cadence), 'cad-1');
    });

    testWidgets('selecting a power source updates the hub', (tester) async {
      final hub = SensorHub();
      hub.register(FakeSensorSource(
        id: 'pwr-1',
        displayName: 'Power meter',
        provides: {SensorQuantity.power},
      ));
      await tester.pumpWidget(
        ShadcnApp(
          localizationsDelegates: [
            ...ShadcnLocalizations.localizationsDelegates,
            AppLocalizations.delegate,
          ],
          supportedLocales: const [Locale('en')],
          home: Scaffold(child: SensorsSection(hub: hub)),
        ),
      );
      await tester.pumpAndSettle();

      hub.select(SensorQuantity.power, 'pwr-1');
      await tester.pumpAndSettle();

      expect(hub.selectionFor(SensorQuantity.power), 'pwr-1');
    });
  });

  // T5-D: the power-meter opt-in toggle. Wording lives only in the ARB file —
  // this only ever asserts the switch's key and the persisted setting, never
  // literal translated copy.
  group('power-meter opt-in toggle', () {
    testWidgets('renders off by default and persists on when toggled', (tester) async {
      await pumpSection(tester);

      expect(core.settings.getPowerMeterOptIn(), isFalse);
      final switchFinder = find.byKey(const Key('power-meter-opt-in-switch'));
      expect(switchFinder, findsOneWidget);
      expect(tester.widget<Switch>(switchFinder).value, isFalse);

      await tester.tap(switchFinder);
      await tester.pumpAndSettle();

      expect(core.settings.getPowerMeterOptIn(), isTrue);
      expect(tester.widget<Switch>(switchFinder).value, isTrue);
    });
  });
}
