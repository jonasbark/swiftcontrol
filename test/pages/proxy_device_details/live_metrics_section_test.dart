import 'package:bike_control/bluetooth/devices/proxy/proxy_device.dart';
import 'package:bike_control/bluetooth/devices/sensors/ble_heart_rate_device.dart';
import 'package:bike_control/gen/l10n.dart';
import 'package:bike_control/pages/proxy_device_details/live_metrics_section.dart';
import 'package:bike_control/pages/proxy_device_details/metric_card.dart';
import 'package:bike_control/pages/proxy_device_details/sensor_source_picker.dart';
import 'package:bike_control/services/sensors/fake_sensor_source.dart';
import 'package:bike_control/services/sensors/sensor_quantity.dart';
import 'package:bike_control/utils/actions/base_actions.dart';
import 'package:bike_control/utils/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:universal_ble/universal_ble.dart';

/// The signals grid: decoupled from `ProxyDevice` (standalone mode) and, per
/// the Claude Design system spec, growing an optional source row on the
/// power/heart/cadence tiles. Mounts the REAL `core.sensors` — the same
/// singleton `Connection` registers into — so this proves the section reacts
/// to the actual hub, not a double. Every test that touches it cleans up via
/// `addTearDown` so later tests start from a clean selection/registration.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'http://127.0.0.1:9',
      anonKey: 'live-metrics-section-test-anon-key',
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
    core.actionHandler = StubActions();
    core.connection.devices.clear();
  });

  tearDown(() {
    core.connection.devices.clear();
  });

  Future<void> pump(WidgetTester tester, {ProxyDevice? device, bool hideWhenDeviceHasNoMetrics = false}) async {
    await tester.pumpWidget(
      ShadcnApp(
        localizationsDelegates: [
          ...ShadcnLocalizations.localizationsDelegates,
          AppLocalizations.delegate,
        ],
        supportedLocales: const [Locale('en')],
        home: Scaffold(
          child: LiveMetricsSection(device: device, hideWhenDeviceHasNoMetrics: hideWhenDeviceHasNoMetrics),
        ),
      ),
    );
    await tester.pump();
  }

  Finder rowIn(String quantityName) => find.descendant(
    of: find.byKey(Key('metric-card-$quantityName')),
    matching: find.byKey(const Key('metric-card-source-row')),
  );

  Color? dotIn(WidgetTester tester, String quantityName) {
    final finder = find.descendant(
      of: find.byKey(Key('metric-card-$quantityName')),
      matching: find.byKey(const Key('metric-card-source-dot')),
    );
    final container = tester.widget<Container>(finder);
    return (container.decoration as BoxDecoration?)?.color;
  }

  group('THE INVARIANT: no external sensors at all', () {
    testWidgets('standalone (no device): every tile shows "--" and no tile has a source row', (tester) async {
      await pump(tester);

      expect(find.byKey(const Key('metric-card-power')), findsOneWidget);
      expect(find.byKey(const Key('metric-card-heartRate')), findsOneWidget);
      expect(find.byKey(const Key('metric-card-cadence')), findsOneWidget);
      expect(find.byKey(const Key('metric-card-speed')), findsOneWidget);
      expect(find.text('--'), findsNWidgets(4));
      expect(rowIn('power'), findsNothing);
      expect(rowIn('heartRate'), findsNothing);
      expect(rowIn('cadence'), findsNothing);
      expect(rowIn('speed'), findsNothing);
    });
  });

  group('a nearby, not-yet-connected sensor', () {
    testWidgets('makes the row appear in the quiet "trainer" state, not the sensor', (tester) async {
      final device = BleHeartRateDevice(BleDevice(deviceId: 'nearby-hr', name: 'TICKR 1234'));
      core.connection.devices.add(device);

      await pump(tester);

      expect(rowIn('heartRate'), findsOneWidget);
      expect(find.text(AppLocalizations.current.sensorSourceTrainer), findsOneWidget);
      expect(dotIn(tester, 'heartRate'), Theme.of(tester.element(rowIn('heartRate'))).colorScheme.mutedForeground);
      // A heart rate strap doesn't provide power or cadence.
      expect(rowIn('power'), findsNothing);
      expect(rowIn('cadence'), findsNothing);
    });
  });

  group('a selected, registered, fresh source', () {
    testWidgets('connected: green dot, the source\'s own display name, and its live value', (tester) async {
      final source = FakeSensorSource(id: 'hr-connected', displayName: 'HR6 0050789', provides: {
        SensorQuantity.heartRate,
      });
      core.sensors.register(source);
      core.sensors.select(SensorQuantity.heartRate, source.id);
      source.emit(SensorQuantity.heartRate, 142);
      addTearDown(() {
        core.sensors.unregister(source.id);
        core.sensors.select(SensorQuantity.heartRate, null);
      });

      await pump(tester);

      expect(find.text('HR6 0050789'), findsOneWidget);
      expect(dotIn(tester, 'heartRate'), const Color(0xFF22C55E));
      // The value/unit rows are unchanged from before this feature — a raw
      // "142", not the combined "142 bpm" the picker's subtitle uses.
      expect(
        find.descendant(of: find.byKey(const Key('metric-card-heartRate')), matching: find.text('142')),
        findsOneWidget,
      );
    });
  });

  group('a selected source not yet registered', () {
    testWidgets('connecting: amber dot, "Connecting…"', (tester) async {
      core.sensors.select(SensorQuantity.cadence, 'ghost-cadence-source');
      addTearDown(() => core.sensors.select(SensorQuantity.cadence, null));

      await pump(tester);

      expect(rowIn('cadence'), findsOneWidget);
      expect(find.text(AppLocalizations.current.sensorConnecting), findsOneWidget);
      expect(dotIn(tester, 'cadence'), const Color(0xFFF59E0B));
    });
  });

  group('a selected, registered source with no reading yet', () {
    testWidgets('waiting for first reading: amber dot', (tester) async {
      final source = FakeSensorSource(id: 'pwr-waiting', displayName: 'Power meter', provides: {
        SensorQuantity.power,
      });
      core.sensors.register(source);
      core.sensors.select(SensorQuantity.power, source.id);
      addTearDown(() {
        core.sensors.unregister(source.id);
        core.sensors.select(SensorQuantity.power, null);
      });

      await pump(tester);

      expect(find.text(AppLocalizations.current.sensorAwaitingFirstReading), findsOneWidget);
      expect(dotIn(tester, 'power'), const Color(0xFFF59E0B));
    });
  });

  group('a selected, registered source that stops reporting', () {
    testWidgets('lost: red dot, signal-lost copy — falls back to the trainer', (tester) async {
      final source = FakeSensorSource(id: 'hr-lost', displayName: 'TICKR 1234', provides: {
        SensorQuantity.heartRate,
      });
      core.sensors.register(source);
      core.sensors.select(SensorQuantity.heartRate, source.id);
      // Reported before, but the only reading on record is already stale —
      // `everReported` (raw value non-null) is true while `droppedOut` is
      // also true, which is exactly the "lost" branch.
      source.emit(SensorQuantity.heartRate, 150, at: DateTime.now().subtract(const Duration(seconds: 30)));
      addTearDown(() {
        core.sensors.unregister(source.id);
        core.sensors.select(SensorQuantity.heartRate, null);
      });

      await pump(tester);

      expect(find.text(AppLocalizations.current.sensorDroppedOut), findsOneWidget);
      expect(dotIn(tester, 'heartRate'), const Color(0xFFEF4444));
      // Fallen back to the trainer: no external value survives to the tile.
      expect(
        find.descendant(of: find.byKey(const Key('metric-card-heartRate')), matching: find.text('--')),
        findsOneWidget,
      );
    });
  });

  group('SPEED', () {
    testWidgets('never shows a source row, even with a selected, connected "speed" source', (tester) async {
      final source = FakeSensorSource(id: 'spd', displayName: 'Speed sensor', provides: {SensorQuantity.speed});
      core.sensors.register(source);
      core.sensors.select(SensorQuantity.speed, source.id);
      source.emit(SensorQuantity.speed, 32);
      addTearDown(() {
        core.sensors.unregister(source.id);
        core.sensors.select(SensorQuantity.speed, null);
      });

      await pump(tester);

      expect(rowIn('speed'), findsNothing);
    });
  });

  group('hideWhenDeviceHasNoMetrics (ProxyDeviceDetailsPage\'s own pixel-fidelity case)', () {
    testWidgets('true + a device with nothing to report yet: renders nothing at all', (tester) async {
      final device = ProxyDevice(BleDevice(deviceId: 'x', name: 'Wahoo KICKR'));
      expect(device.fitnessBike, isNull);

      await pump(tester, device: device, hideWhenDeviceHasNoMetrics: true);

      expect(find.byType(MetricCard), findsNothing);
    });

    testWidgets('false (home page\'s default): the same device still renders the grid', (tester) async {
      final device = ProxyDevice(BleDevice(deviceId: 'x', name: 'Wahoo KICKR'));

      await pump(tester, device: device);

      expect(find.byType(MetricCard), findsNWidgets(4));
    });
  });

  testWidgets('tapping a source row opens the picker for that quantity', (tester) async {
    final nearby = BleHeartRateDevice(BleDevice(deviceId: 'nearby-hr-2', name: 'TICKR 9999'));
    core.connection.devices.add(nearby);

    await pump(tester);
    await tester.tap(rowIn('heartRate'));
    await tester.pumpAndSettle();

    expect(find.byType(SensorSourcePicker), findsOneWidget);
  });

  testWidgets('a sensor discovered after the section is already mounted flips a row live', (tester) async {
    await pump(tester);
    expect(rowIn('heartRate'), findsNothing);

    final device = BleHeartRateDevice(BleDevice(deviceId: 'hr-live', name: 'Live TICKR'));
    core.connection.devices.add(device);
    core.connection.signalChange(device);
    await tester.pumpAndSettle();

    // Discovered but not yet connected: the row appears in the quiet
    // "trainer" state — no remount of the section was needed for it to show.
    expect(rowIn('heartRate'), findsOneWidget);
    expect(find.text(AppLocalizations.current.sensorSourceTrainer), findsOneWidget);
  });
}
