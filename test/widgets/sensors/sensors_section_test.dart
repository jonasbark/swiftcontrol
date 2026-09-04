import 'package:bike_control/gen/l10n.dart';
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
        home: SensorsSection(hub: hub),
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
}
