import 'package:bike_control/bluetooth/devices/proxy/proxy_device.dart';
import 'package:bike_control/bluetooth/devices/sensors/ble_heart_rate_device.dart';
import 'package:bike_control/bluetooth/devices/sensors/ble_power_device.dart';
import 'package:bike_control/bluetooth/emulation/emulated_ble_platform.dart';
import 'package:bike_control/gen/l10n.dart';
import 'package:bike_control/pages/proxy_device_details/live_metrics_section.dart';
import 'package:bike_control/pages/proxy_device_details/metric_card.dart';
import 'package:bike_control/services/sensors/ble_sensor_source.dart';
import 'package:bike_control/services/sensors/fake_sensor_source.dart';
import 'package:bike_control/services/sensors/sensor_quantity.dart';
import 'package:bike_control/utils/actions/base_actions.dart';
import 'package:bike_control/utils/core.dart';
import 'package:bike_control/utils/iap/iap_manager.dart';
import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:flutter_local_notifications_platform_interface/flutter_local_notifications_platform_interface.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:universal_ble/universal_ble.dart';

/// No-op local-notifications backend — `Connection._connect` posts a
/// "connected" notification on success, and the plugin's static platform
/// instance is only set by real plugin registration. Mirrors
/// `test/integration/harness/test_env.dart`'s own fake (and the deleted
/// `sensor_source_picker_test.dart`'s, which this file's connect-ordering
/// tests are ported from).
class _FakeLocalNotificationsPlatform extends FlutterLocalNotificationsPlatform {
  @override
  Future<void> show({required int id, String? title, String? body, String? payload}) async {}

  @override
  Future<void> cancel({required int id}) async {}

  @override
  Future<void> cancelAll() async {}
}

/// The signals grid: decoupled from `ProxyDevice` (standalone mode) and, per
/// the Claude Design system spec (and direct author feedback that a picker
/// sheet was the wrong shape), the app's ONE sensor surface — each of the
/// power/heart/cadence tiles lists its sources INLINE as a segmented control,
/// no dropdown, no sheet. Mounts the REAL `core.sensors` — the same singleton
/// `Connection` registers into — so this proves the section reacts to the
/// actual hub, not a double. Every test that touches it cleans up via
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
    FlutterLocalNotificationsPlatform.instance = _FakeLocalNotificationsPlatform();
    IAPManager.instance.setProForTesting(enabled: false);
  });

  tearDown(() {
    // NOT `core.connection.stop()` here: most tests in this file never set a
    // fake `UniversalBle` instance, and `stop()` calls
    // `getBluetoothAvailabilityState()`, which throws with no platform
    // channel to answer it. The tests that DO drive a real (dis)connect
    // through `Connection` call `stop()` themselves, inside the test body —
    // see their own comment on why it has to happen there.
    core.connection.devices.clear();
    IAPManager.instance.setProForTesting(enabled: false);
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

  Finder controlIn(String quantityName) => find.descendant(
    of: find.byKey(Key('metric-card-$quantityName')),
    matching: find.byKey(const Key('metric-card-source-control')),
  );

  Finder segmentIn(String quantityName, String id) => find.descendant(
    of: find.byKey(Key('metric-card-$quantityName')),
    matching: find.byKey(Key('metric-card-source-option-$id')),
  );

  Color? dotColor(WidgetTester tester, String quantityName, String id) {
    final finder = find.descendant(
      of: find.byKey(Key('metric-card-$quantityName')),
      matching: find.byKey(Key('metric-card-source-dot-$id')),
    );
    final container = tester.widget<Container>(finder);
    return (container.decoration as BoxDecoration?)?.color;
  }

  FakePeripheral strapPeripheral({required String deviceId, String name = 'TICKR 1234'}) => FakePeripheral(
    deviceId: deviceId,
    name: name,
    advertisedServices: [BleSensorSource.heartRateServiceUuid],
    services: [
      BleService(BleSensorSource.heartRateServiceUuid, [
        BleCharacteristic(BleSensorSource.heartRateMeasurementUuid, [CharacteristicProperty.notify], const []),
      ]),
    ],
  );

  // A combo power meter — `BlePowerDevice.provides` is `{power, cadence}` —
  // used to prove the multi-quantity guard: a sensor selected for two
  // quantities must not be disconnected just because ONE of them switches
  // back to Trainer.
  FakePeripheral powerPeripheral({required String deviceId, String name = 'ASSIOMA DUO'}) => FakePeripheral(
    deviceId: deviceId,
    name: name,
    advertisedServices: [BleSensorSource.cyclingPowerServiceUuid],
    services: [
      BleService(BleSensorSource.cyclingPowerServiceUuid, [
        BleCharacteristic(BleSensorSource.cyclingPowerMeasurementUuid, [CharacteristicProperty.notify], const []),
      ]),
    ],
  );

  group('THE INVARIANT: no external sensors at all', () {
    testWidgets('standalone (no device): every tile shows "--" and no tile has a source control', (tester) async {
      await pump(tester);

      expect(find.byKey(const Key('metric-card-power')), findsOneWidget);
      expect(find.byKey(const Key('metric-card-heartRate')), findsOneWidget);
      expect(find.byKey(const Key('metric-card-cadence')), findsOneWidget);
      expect(find.byKey(const Key('metric-card-speed')), findsOneWidget);
      expect(find.text('--'), findsNWidgets(4));
      expect(controlIn('power'), findsNothing);
      expect(controlIn('heartRate'), findsNothing);
      expect(controlIn('cadence'), findsNothing);
      expect(controlIn('speed'), findsNothing);

      // The equal-height fix must be a no-op here: with no card growing a
      // source list, all four tiles were already the same height before
      // this feature existed, and must stay exactly that way — see
      // `_EqualHeightRow`'s own doc comment on why it only re-lays out a
      // child that is SHORTER than its row.
      final powerHeight = tester.getSize(find.byKey(const Key('metric-card-power'))).height;
      final heartHeight = tester.getSize(find.byKey(const Key('metric-card-heartRate'))).height;
      final cadenceHeight = tester.getSize(find.byKey(const Key('metric-card-cadence'))).height;
      final speedHeight = tester.getSize(find.byKey(const Key('metric-card-speed'))).height;
      expect(powerHeight, heartHeight);
      expect(cadenceHeight, speedHeight);
    });
  });

  group('equal-height rows (direct author feedback: "otherwise it looks odd")', () {
    testWidgets(
      'a card with a source list and its short row-mate render the SAME height, top-aligned content',
      (tester) async {
        // A nearby, not-yet-connected sensor is enough to grow HEART's
        // inline source list (Trainer + the sensor itself) — POWER has no
        // candidate at all, so it stays the short, list-less card. Exactly
        // the mismatch from the author's screenshot.
        final device = BleHeartRateDevice(BleDevice(deviceId: 'equal-height-hr', name: 'TICKR 5555'));
        core.connection.devices.add(device);
        addTearDown(() => core.connection.devices.clear());

        await pump(tester);

        // The fixture actually reproduces the reported mismatch — HEART
        // really does carry extra content POWER doesn't.
        expect(controlIn('heartRate'), findsOneWidget);
        expect(controlIn('power'), findsNothing);

        final powerCard = find.byKey(const Key('metric-card-power'));
        final heartCard = find.byKey(const Key('metric-card-heartRate'));
        expect(tester.getSize(powerCard).height, tester.getSize(heartCard).height);

        // Top-aligned, not centred: POWER's label sits at the same y as
        // HEART's label, even though POWER's container is now taller than
        // its own (short) content.
        final powerLabelTop = tester.getTopLeft(find.descendant(of: powerCard, matching: find.text('POWER'))).dy;
        final heartLabelTop = tester.getTopLeft(find.descendant(of: heartCard, matching: find.text('HEART'))).dy;
        expect(powerLabelTop, heartLabelTop);
      },
    );

    testWidgets('renders without throwing when laid out with unbounded height (inside a scroll view)', (
      tester,
    ) async {
      // The trap: a naive `IntrinsicHeight` + `CrossAxisAlignment.stretch`
      // fix throws under an unbounded incoming height. Both of this
      // section's real call sites (`ProxyDeviceDetailsPage`, the home page)
      // render it inside a scroll view, so this is the shape that matters —
      // an unconstrained `Column` inside a `SingleChildScrollView`, never a
      // tightly-bounded `Scaffold` body like every other test in this file
      // uses.
      final device = BleHeartRateDevice(BleDevice(deviceId: 'unbounded-hr', name: 'TICKR 6666'));
      core.connection.devices.add(device);
      addTearDown(() => core.connection.devices.clear());

      await tester.pumpWidget(
        ShadcnApp(
          localizationsDelegates: [
            ...ShadcnLocalizations.localizationsDelegates,
            AppLocalizations.delegate,
          ],
          supportedLocales: const [Locale('en')],
          home: Scaffold(
            child: SingleChildScrollView(
              child: Column(
                children: const [LiveMetricsSection()],
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      // Still renders correctly once unbounded height is survived — not
      // just "didn't crash".
      expect(find.byKey(const Key('metric-card-power')), findsOneWidget);
      expect(find.byKey(const Key('metric-card-heartRate')), findsOneWidget);
    });
  });

  group('a nearby, not-yet-connected sensor', () {
    testWidgets('lists Trainer (selected, quiet) AND the sensor itself (not connected) inline — no sheet needed', (
      tester,
    ) async {
      final device = BleHeartRateDevice(BleDevice(deviceId: 'nearby-hr', name: 'TICKR 1234'));
      core.connection.devices.add(device);

      await pump(tester);

      expect(controlIn('heartRate'), findsOneWidget);
      expect(segmentIn('heartRate', 'trainer'), findsOneWidget);
      expect(segmentIn('heartRate', device.source.id), findsOneWidget);
      expect(
        find.descendant(
          of: segmentIn('heartRate', 'trainer'),
          matching: find.text(AppLocalizations.current.sensorSourceTrainer),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: segmentIn('heartRate', device.source.id), matching: find.text('TICKR 1234')),
        findsOneWidget,
      );
      // Each row carries its own subtitle explaining what it means —
      // the whole point of the list redesign.
      expect(
        find.descendant(
          of: segmentIn('heartRate', 'trainer'),
          matching: find.text(AppLocalizations.current.sensorSourceTrainerSubtitle),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: segmentIn('heartRate', device.source.id),
          matching: find.text(AppLocalizations.current.sensorSourceNotConnectedSubtitle),
        ),
        findsOneWidget,
      );
      expect(
        dotColor(tester, 'heartRate', 'trainer'),
        Theme.of(tester.element(controlIn('heartRate'))).colorScheme.mutedForeground,
      );
      // A heart rate strap doesn't provide power or cadence.
      expect(controlIn('power'), findsNothing);
      expect(controlIn('cadence'), findsNothing);
    });
  });

  group('a selected, registered, fresh source', () {
    testWidgets('connected: green dot on its own segment, the source\'s own display name, and its live value', (
      tester,
    ) async {
      final source = FakeSensorSource(
        id: 'hr-connected',
        displayName: 'HR6 0050789',
        provides: {
          SensorQuantity.heartRate,
        },
      );
      core.sensors.register(source);
      core.sensors.select(SensorQuantity.heartRate, source.id);
      source.emit(SensorQuantity.heartRate, 142);
      addTearDown(() {
        core.sensors.unregister(source.id);
        core.sensors.select(SensorQuantity.heartRate, null);
      });

      await pump(tester);

      expect(
        find.descendant(of: segmentIn('heartRate', source.id), matching: find.text('HR6 0050789')),
        findsOneWidget,
      );
      // Selected AND streaming: the "connected" subtitle reads as active,
      // not merely "linked somewhere else" (see the DIFFERENT-quantity test
      // below for that other half of the same state).
      expect(
        find.descendant(
          of: segmentIn('heartRate', source.id),
          matching: find.text(AppLocalizations.current.sensorSourceConnectedSubtitle),
        ),
        findsOneWidget,
      );
      expect(dotColor(tester, 'heartRate', source.id), const Color(0xFF22C55E));
      // The value/unit rows are unchanged from before this feature — a raw
      // "142", not the combined "142 bpm" the deleted picker's subtitle used.
      expect(
        find.descendant(of: find.byKey(const Key('metric-card-heartRate')), matching: find.text('142')),
        findsOneWidget,
      );
    });

    testWidgets('a source registered for a DIFFERENT quantity still shows connected (green) here when unselected', (
      tester,
    ) async {
      // A combo sensor: selected for POWER already, never touched for
      // CADENCE. Its own BLE link is genuinely up — the CADENCE tile's
      // segment for it must say so, even though CADENCE is still on Trainer.
      final source = FakeSensorSource(
        id: 'combo-1',
        displayName: 'Combo meter',
        provides: {
          SensorQuantity.power,
          SensorQuantity.cadence,
        },
      );
      core.sensors.register(source);
      core.sensors.select(SensorQuantity.power, source.id);
      addTearDown(() {
        core.sensors.unregister(source.id);
        core.sensors.select(SensorQuantity.power, null);
      });

      await pump(tester);

      expect(segmentIn('cadence', 'trainer'), findsOneWidget);
      expect(
        find.descendant(
          of: segmentIn('cadence', 'trainer'),
          matching: find.text(AppLocalizations.current.sensorSourceTrainer),
        ),
        findsOneWidget,
      );
      expect(dotColor(tester, 'cadence', source.id), const Color(0xFF22C55E));
      // Connected, but not CADENCE's own pick — a different subtitle from
      // the "streaming its own reading" one above: this row means "tap to
      // use it here too", not "this is already your source".
      expect(
        find.descendant(
          of: segmentIn('cadence', source.id),
          matching: find.text(AppLocalizations.current.sensorSourceConnectedElsewhereSubtitle),
        ),
        findsOneWidget,
      );
    });
  });

  group('a selected source not yet registered', () {
    testWidgets('ghost segment: amber dot, "Connecting…", alongside Trainer', (tester) async {
      core.sensors.select(SensorQuantity.cadence, 'ghost-cadence-source');
      addTearDown(() => core.sensors.select(SensorQuantity.cadence, null));

      await pump(tester);

      expect(controlIn('cadence'), findsOneWidget);
      expect(segmentIn('cadence', 'trainer'), findsOneWidget);
      expect(segmentIn('cadence', 'ghost-cadence-source'), findsOneWidget);
      expect(
        find.descendant(
          of: segmentIn('cadence', 'ghost-cadence-source'),
          matching: find.text(AppLocalizations.current.sensorConnecting),
        ),
        findsOneWidget,
      );
      // No real candidate to attach a live "connecting" state to — the
      // subtitle says so explicitly, distinct from a real in-flight BLE
      // handshake's own subtitle (see the waiting-for-first-reading group).
      expect(
        find.descendant(
          of: segmentIn('cadence', 'ghost-cadence-source'),
          matching: find.text(AppLocalizations.current.sensorSourceConnectingGhostSubtitle),
        ),
        findsOneWidget,
      );
      expect(dotColor(tester, 'cadence', 'ghost-cadence-source'), const Color(0xFFF59E0B));
    });
  });

  group('a selected, registered source with no reading yet', () {
    testWidgets('waiting for first reading: amber dot on its own segment — the label stays the source\'s own name', (
      tester,
    ) async {
      final source = FakeSensorSource(
        id: 'pwr-waiting',
        displayName: 'Power meter',
        provides: {
          SensorQuantity.power,
        },
      );
      core.sensors.register(source);
      core.sensors.select(SensorQuantity.power, source.id);
      addTearDown(() {
        core.sensors.unregister(source.id);
        core.sensors.select(SensorQuantity.power, null);
      });

      await pump(tester);

      // Unlike the deleted single-row design, a real candidate's label is
      // always its own name — only the dot carries "waiting" here; there is
      // no separate ghost/no-name segment involved (that only happens when
      // the selection matches no known candidate at all — see the
      // "not yet registered" group above).
      expect(
        find.descendant(of: segmentIn('power', source.id), matching: find.text('Power meter')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: segmentIn('power', source.id),
          matching: find.text(AppLocalizations.current.sensorAwaitingFirstReading),
        ),
        findsOneWidget,
      );
      expect(dotColor(tester, 'power', source.id), const Color(0xFFF59E0B));
    });
  });

  group('a selected, registered source that stops reporting', () {
    testWidgets('lost: red dot on its own segment — falls back to the trainer value', (tester) async {
      final source = FakeSensorSource(
        id: 'hr-lost',
        displayName: 'TICKR 1234',
        provides: {
          SensorQuantity.heartRate,
        },
      );
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

      expect(dotColor(tester, 'heartRate', source.id), const Color(0xFFEF4444));
      // The subtitle names exactly what happened and what the rider is
      // seeing instead — this is the "value has fallen back to the trainer"
      // case the row has to spell out, not leave to the dot colour alone.
      expect(
        find.descendant(
          of: segmentIn('heartRate', source.id),
          matching: find.text(AppLocalizations.current.sensorDroppedOut),
        ),
        findsOneWidget,
      );
      // Fallen back to the trainer: no external value survives to the tile.
      expect(
        find.descendant(of: find.byKey(const Key('metric-card-heartRate')), matching: find.text('--')),
        findsOneWidget,
      );
    });
  });

  group('SPEED', () {
    testWidgets('never shows a source control, even with a selected, connected "speed" source', (tester) async {
      final source = FakeSensorSource(id: 'spd', displayName: 'Speed sensor', provides: {SensorQuantity.speed});
      core.sensors.register(source);
      core.sensors.select(SensorQuantity.speed, source.id);
      source.emit(SensorQuantity.speed, 32);
      addTearDown(() {
        core.sensors.unregister(source.id);
        core.sensors.select(SensorQuantity.speed, null);
      });

      await pump(tester);

      expect(controlIn('speed'), findsNothing);
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

  testWidgets('tapping a source segment selects it directly — no sheet, no picker opens', (tester) async {
    // Already registered (no BLE connect step needed on tap) — the real
    // connect-through-a-tap path, with its BLE machinery, is the dedicated
    // "CRITICAL — connect ordering" group below.
    final source = FakeSensorSource(
      id: 'hr-direct-select',
      displayName: 'TICKR 9999',
      provides: {
        SensorQuantity.heartRate,
      },
    );
    core.sensors.register(source);
    IAPManager.instance.setProForTesting(enabled: true);
    addTearDown(() {
      core.sensors.unregister(source.id);
      core.sensors.select(SensorQuantity.heartRate, null);
    });

    await pump(tester);
    // The segmented control scrolls horizontally (`MetricCard._sourceControl`)
    // for a quantity with enough sources that they cannot all fit — bring the
    // target into the viewport first so the tap cannot silently miss it.
    await tester.ensureVisible(segmentIn('heartRate', source.id));
    await tester.tap(segmentIn('heartRate', source.id));
    await tester.pumpAndSettle();

    expect(core.sensors.selectionFor(SensorQuantity.heartRate), source.id);
  });

  testWidgets('a sensor discovered after the section is already mounted flips its own segment live', (tester) async {
    await pump(tester);
    expect(controlIn('heartRate'), findsNothing);

    final device = BleHeartRateDevice(BleDevice(deviceId: 'hr-live', name: 'Live TICKR'));
    core.connection.devices.add(device);
    core.connection.signalChange(device);
    await tester.pumpAndSettle();

    // Discovered but not yet connected: Trainer plus the sensor's own
    // segment appear — no remount of the section was needed for it to show.
    expect(segmentIn('heartRate', 'trainer'), findsOneWidget);
    expect(segmentIn('heartRate', device.source.id), findsOneWidget);
  });

  group('Pro gating', () {
    testWidgets('selecting Trainer clears the selection, with no BLE side effect and no Pro gate', (tester) async {
      IAPManager.instance.setProForTesting(enabled: false);
      core.sensors.select(SensorQuantity.heartRate, 'was-something');
      addTearDown(() => core.sensors.select(SensorQuantity.heartRate, null));

      await pump(tester);
      await tester.ensureVisible(segmentIn('heartRate', 'trainer'));
      await tester.tap(segmentIn('heartRate', 'trainer'));
      await tester.pumpAndSettle();

      expect(core.sensors.selectionFor(SensorQuantity.heartRate), isNull);
    });
  });

  group('CRITICAL — connect ordering', () {
    testWidgets(
      'tapping a not-yet-connected sensor\'s segment persists consent BEFORE connecting, '
      'then drives the device to a real connected state',
      (tester) async {
        IAPManager.instance.setProForTesting(enabled: true);
        final ble = FakeUniversalBlePlatform();
        UniversalBle.setInstance(ble);
        final peripheral = strapPeripheral(deviceId: 'hr-pick-3');
        ble.addPeripheral(peripheral);
        final device = BleHeartRateDevice(peripheral.scanResult);
        core.connection.devices.add(device);
        addTearDown(() {
          core.sensors.unregister(device.source.id);
          core.sensors.select(SensorQuantity.heartRate, null);
        });
        expect(device.shouldAutoConnect, isFalse);

        await pump(tester);
        await tester.ensureVisible(segmentIn('heartRate', device.source.id));
        await tester.tap(segmentIn('heartRate', device.source.id));
        await tester.pumpAndSettle();

        expect(device.isConnected, isTrue);
        // Persisted, not just in-memory — AND proof of the load-bearing
        // ordering: had the flag been written after calling connect() instead
        // of before, `shouldAutoConnect` would have read false at connect()
        // time, `connect()` would have early-returned, and `isConnected` above
        // would still be false no matter what the flag reads now.
        expect(core.settings.getSensorAutoConnect(device.device.deviceId), isTrue);
        expect(core.sensors.selectionFor(SensorQuantity.heartRate), device.source.id);

        // `Connection`'s BLE connection-state listener re-evaluates on every
        // (dis)connect and would otherwise leave a periodic gamepad-search
        // timer pending past this test's end (`performScanning`'s doc
        // comment) — `flutter_test`'s pending-timer check runs at the end of
        // the test body itself, before any `tearDown`/`addTearDown` gets a
        // turn, so this has to happen here rather than in either of those.
        await core.connection.stop();
      },
    );

    // Deliberately no automated widget test drives a FAILED connect through
    // the real `Connection`/`FakeUniversalBlePlatform` stack, and no test
    // drives the Pro-denied dialog path to completion — both are pre-existing
    // gaps this file inherits from the deleted `sensor_source_picker_test
    // .dart`, which carried the same limitation for the same reason: under
    // `testWidgets`' FakeAsync zone, a rejected `device.connect()` does not
    // resolve within any bounded number of `pump()`/`pumpAndSettle()` calls,
    // independent of which error it rejects with, and `showGoProDialog` pulls
    // in the full purchase-flow UI. Both paths are covered by code review
    // instead: `_select`'s catch block forwards through `recordError` before
    // rethrowing (verified above the fold), and the Pro gate
    // (`sourceId != null && !isProEnabledForCurrentDevice`) is exercised for
    // its "does not apply to Trainer" half by the test above.
  });

  group('disconnect', () {
    testWidgets(
      'long-pressing the selected, connected segment clears the consent flag BEFORE disconnecting, '
      'and the selection falls back to Trainer',
      (tester) async {
        IAPManager.instance.setProForTesting(enabled: true);
        final ble = FakeUniversalBlePlatform();
        UniversalBle.setInstance(ble);
        final peripheral = strapPeripheral(deviceId: 'hr-pick-4');
        ble.addPeripheral(peripheral);
        final device = BleHeartRateDevice(peripheral.scanResult);
        core.connection.devices.add(device);
        addTearDown(() {
          core.sensors.unregister(device.source.id);
          core.sensors.select(SensorQuantity.heartRate, null);
        });

        // Get to a genuinely connected+registered+selected state first, via
        // the same tap the connect-ordering test above proves.
        await pump(tester);
        await tester.ensureVisible(segmentIn('heartRate', device.source.id));
        await tester.tap(segmentIn('heartRate', device.source.id));
        await tester.pumpAndSettle();
        expect(device.isConnected, isTrue);
        expect(core.sensors.selectionFor(SensorQuantity.heartRate), device.source.id);

        await tester.ensureVisible(segmentIn('heartRate', device.source.id));
        await tester.longPress(segmentIn('heartRate', device.source.id));
        await tester.pumpAndSettle();

        expect(core.settings.getSensorAutoConnect(device.device.deviceId), isFalse);
        expect(device.isConnected, isFalse);
        // `forget: true` cascades: the quantity selection that pointed at this
        // source falls back to Trainer rather than being left dangling.
        expect(core.sensors.selectionFor(SensorQuantity.heartRate), isNull);
        // `persistForget: false`: not on the permanent ignore list, so it stays
        // reconnectable — proven indirectly here by the flag call above using
        // exactly that pair of arguments (see `LiveMetricsSection._disconnect`'s
        // doc comment); asserting the ignore list itself is
        // `ignored_devices_dialog`/`Settings.getIgnoredDevices` territory, out
        // of scope for this file.

        // See the connect-ordering test's own comment on why this has to run
        // here, inside the test body, rather than in a teardown hook.
        await core.connection.stop();
      },
    );

    testWidgets('long-pressing Trainer does nothing (no onDisconnect wired)', (tester) async {
      // A bare "nothing selected, nothing nearby" tile renders no control at
      // all (THE INVARIANT) — a nearby sensor is the minimal setup that
      // makes the Trainer segment itself exist to long-press.
      final nearby = BleHeartRateDevice(BleDevice(deviceId: 'nearby-hr-3', name: 'TICKR 0001'));
      core.connection.devices.add(nearby);

      await pump(tester);

      await tester.ensureVisible(segmentIn('heartRate', 'trainer'));
      await tester.longPress(segmentIn('heartRate', 'trainer'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(core.sensors.selectionFor(SensorQuantity.heartRate), isNull);
    });
  });

  group('selecting Trainer disconnects the now-idle sensor (direct author feedback)', () {
    testWidgets(
      'a sensor serving only this quantity: selecting Trainer disconnects it and clears its consent flag',
      (tester) async {
        IAPManager.instance.setProForTesting(enabled: true);
        final ble = FakeUniversalBlePlatform();
        UniversalBle.setInstance(ble);
        final peripheral = strapPeripheral(deviceId: 'hr-trainer-back-1');
        ble.addPeripheral(peripheral);
        final device = BleHeartRateDevice(peripheral.scanResult);
        core.connection.devices.add(device);
        addTearDown(() {
          core.sensors.unregister(device.source.id);
          core.sensors.select(SensorQuantity.heartRate, null);
        });

        await pump(tester);
        await tester.ensureVisible(segmentIn('heartRate', device.source.id));
        await tester.tap(segmentIn('heartRate', device.source.id));
        await tester.pumpAndSettle();
        expect(device.isConnected, isTrue);
        expect(core.sensors.selectionFor(SensorQuantity.heartRate), device.source.id);

        await tester.ensureVisible(segmentIn('heartRate', 'trainer'));
        await tester.tap(segmentIn('heartRate', 'trainer'));
        await tester.pumpAndSettle();

        expect(core.sensors.selectionFor(SensorQuantity.heartRate), isNull);
        expect(device.isConnected, isFalse);
        expect(core.settings.getSensorAutoConnect(device.device.deviceId), isFalse);

        // See the connect-ordering test's own comment on why this has to run
        // here, inside the test body, rather than in a teardown hook.
        await core.connection.stop();
      },
    );

    // THE CASE THAT MUST BE GOT RIGHT: a combo power meter serving BOTH
    // power and cadence (`BlePowerDevice.provides`). Switching POWER back to
    // Trainer must NOT drop the meter — it is still CADENCE's live source. A
    // naive "always disconnect on Trainer" implementation passes every other
    // test in this file and still fails this one.
    testWidgets(
      'a sensor selected for TWO quantities stays connected when only ONE switches back to Trainer',
      (tester) async {
        IAPManager.instance.setProForTesting(enabled: true);
        final ble = FakeUniversalBlePlatform();
        UniversalBle.setInstance(ble);
        final peripheral = powerPeripheral(deviceId: 'combo-power-1');
        ble.addPeripheral(peripheral);
        final device = BlePowerDevice(peripheral.scanResult);
        core.connection.devices.add(device);
        addTearDown(() {
          core.sensors.unregister(device.source.id);
          core.sensors.select(SensorQuantity.power, null);
          core.sensors.select(SensorQuantity.cadence, null);
        });

        await pump(tester);
        // Select it for POWER first — the real connect-through-a-tap path.
        await tester.ensureVisible(segmentIn('power', device.source.id));
        await tester.tap(segmentIn('power', device.source.id));
        await tester.pumpAndSettle();
        expect(device.isConnected, isTrue);
        expect(core.sensors.selectionFor(SensorQuantity.power), device.source.id);

        // Already registered and connected — selecting it for CADENCE too
        // just binds the hub, exactly like a rider using the same combo
        // meter for both readings.
        await tester.ensureVisible(segmentIn('cadence', device.source.id));
        await tester.tap(segmentIn('cadence', device.source.id));
        await tester.pumpAndSettle();
        expect(core.sensors.selectionFor(SensorQuantity.cadence), device.source.id);

        // Switch POWER back to Trainer.
        await tester.ensureVisible(segmentIn('power', 'trainer'));
        await tester.tap(segmentIn('power', 'trainer'));
        await tester.pumpAndSettle();

        expect(core.sensors.selectionFor(SensorQuantity.power), isNull);
        // CADENCE's own selection is untouched.
        expect(core.sensors.selectionFor(SensorQuantity.cadence), device.source.id);
        // Still connected — it is still serving CADENCE.
        expect(device.isConnected, isTrue);
        // Consent flag left exactly as it was — no disconnect was attempted.
        expect(core.settings.getSensorAutoConnect(device.device.deviceId), isTrue);

        await core.connection.stop();
      },
    );

    testWidgets('Trainer already selected: selecting it again attempts no disconnect and writes no flag', (
      tester,
    ) async {
      // A nearby, unregistered strap makes the Trainer segment exist to tap
      // (THE INVARIANT: no candidates at all means no control renders) while
      // leaving Trainer itself already selected for heartRate.
      final nearby = BleHeartRateDevice(BleDevice(deviceId: 'nearby-hr-trainer-noop', name: 'TICKR 0002'));
      core.connection.devices.add(nearby);
      expect(core.sensors.selectionFor(SensorQuantity.heartRate), isNull);
      expect(core.settings.getSensorAutoConnect(nearby.device.deviceId), isFalse);

      await pump(tester);
      await tester.ensureVisible(segmentIn('heartRate', 'trainer'));
      await tester.tap(segmentIn('heartRate', 'trainer'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(core.sensors.selectionFor(SensorQuantity.heartRate), isNull);
      // No disconnect was ever attempted against the nearby, unrelated
      // device — its consent flag is untouched.
      expect(core.settings.getSensorAutoConnect(nearby.device.deviceId), isFalse);
    });
  });
}
