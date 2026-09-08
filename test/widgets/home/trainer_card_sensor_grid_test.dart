import 'package:bike_control/gen/l10n.dart';
import 'package:bike_control/services/sensors/fake_sensor_source.dart';
import 'package:bike_control/services/sensors/sensor_hub.dart';
import 'package:bike_control/services/sensors/sensor_quantity.dart';
import 'package:bike_control/widgets/home/trainer_card_sensor_grid.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

/// Trainer-card sensor grid (feedback: "Integrate the connected sensors in
/// the Trainer card on the home page as grid with its value"). Mirrors
/// `test/widgets/sensors/sensors_section_test.dart`'s harness — a fresh,
/// injected `SensorHub` per test, never the app-wide `core.sensors`, so
/// nothing here can leak a selection into another file's tests.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpGrid(WidgetTester tester, SensorHub hub) async {
    await tester.pumpWidget(
      ShadcnApp(
        localizationsDelegates: [
          ...ShadcnLocalizations.localizationsDelegates,
          AppLocalizations.delegate,
        ],
        supportedLocales: const [Locale('en')],
        home: Scaffold(child: TrainerCardSensorGrid(hub: hub)),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('the invariant: nothing selected means nothing shown', () {
    test('sensorGridHasContent is false for a hub with no selections', () {
      final hub = SensorHub();

      expect(sensorGridHasContent(hub), isFalse);
    });

    testWidgets('renders no grid at all', (tester) async {
      final hub = SensorHub();

      await pumpGrid(tester, hub);

      expect(find.byKey(const Key('trainer-card-sensor-grid')), findsNothing);
    });
  });

  group('a connected, selected sensor', () {
    testWidgets('shows a cell with its live value and unit', (tester) async {
      final hub = SensorHub();
      final strap = FakeSensorSource(id: 'strap', displayName: 'TICKR 1234', provides: {
        SensorQuantity.heartRate,
      });
      hub.register(strap);
      hub.select(SensorQuantity.heartRate, 'strap');
      strap.emit(SensorQuantity.heartRate, 150);

      expect(sensorGridHasContent(hub), isTrue);
      await pumpGrid(tester, hub);

      expect(find.byKey(const Key('trainer-card-sensor-grid')), findsOneWidget);
      expect(find.byKey(const Key('trainer-card-sensor-cell-heartRate')), findsOneWidget);
      expect(find.text(AppLocalizations.current.sensorValueHeartRate(150)), findsOneWidget);
      expect(find.text(AppLocalizations.current.sensorQuantityHeartRate), findsOneWidget);
    });

    testWidgets('shows a placeholder before the first reading arrives', (tester) async {
      final hub = SensorHub();
      hub.register(FakeSensorSource(id: 'strap', displayName: 'TICKR 1234', provides: {
        SensorQuantity.heartRate,
      }));
      hub.select(SensorQuantity.heartRate, 'strap');

      await pumpGrid(tester, hub);

      expect(find.byKey(const Key('trainer-card-sensor-cell-heartRate')), findsOneWidget);
      expect(find.text(AppLocalizations.current.sensorNoReadingYet), findsOneWidget);
    });

    testWidgets('a second connected quantity adds a second cell, in the same grid', (tester) async {
      final hub = SensorHub();
      final power = FakeSensorSource(id: 'pwr', displayName: 'Power meter', provides: {
        SensorQuantity.power,
        SensorQuantity.cadence,
      });
      hub.register(power);
      hub.select(SensorQuantity.power, 'pwr');
      hub.select(SensorQuantity.cadence, 'pwr');
      power.emit(SensorQuantity.power, 212);
      power.emit(SensorQuantity.cadence, 88);

      await pumpGrid(tester, hub);

      expect(find.byKey(const Key('trainer-card-sensor-cell-power')), findsOneWidget);
      expect(find.byKey(const Key('trainer-card-sensor-cell-cadence')), findsOneWidget);
      expect(find.text(AppLocalizations.current.sensorValuePower(212)), findsOneWidget);
      expect(find.text(AppLocalizations.current.sensorValueCadence(88)), findsOneWidget);
    });

    testWidgets('the cell live-updates when the reading changes, with no rebuild from above', (tester) async {
      final hub = SensorHub();
      final strap = FakeSensorSource(id: 'strap', displayName: 'TICKR 1234', provides: {
        SensorQuantity.heartRate,
      });
      hub.register(strap);
      hub.select(SensorQuantity.heartRate, 'strap');
      strap.emit(SensorQuantity.heartRate, 150);

      await pumpGrid(tester, hub);
      expect(find.text(AppLocalizations.current.sensorValueHeartRate(150)), findsOneWidget);

      strap.emit(SensorQuantity.heartRate, 151);
      await tester.pump();

      expect(find.text(AppLocalizations.current.sensorValueHeartRate(151)), findsOneWidget);
      expect(find.text(AppLocalizations.current.sensorValueHeartRate(150)), findsNothing);
    });
  });

  group('selected but not connected', () {
    test('sensorGridHasContent is false for a selection whose source never registered', () {
      final hub = SensorHub();

      hub.select(SensorQuantity.heartRate, 'ghost-strap');

      expect(sensorGridHasContent(hub), isFalse);
    });

    testWidgets('draws no cell for it', (tester) async {
      final hub = SensorHub();
      hub.select(SensorQuantity.heartRate, 'ghost-strap');

      await pumpGrid(tester, hub);

      expect(find.byKey(const Key('trainer-card-sensor-grid')), findsNothing);
      expect(find.byKey(const Key('trainer-card-sensor-cell-heartRate')), findsNothing);
    });

    test('sensorGridHasContent is false once a connected source is unregistered again', () {
      final hub = SensorHub();
      final strap = FakeSensorSource(id: 'strap', displayName: 'TICKR 1234', provides: {
        SensorQuantity.heartRate,
      });
      hub.register(strap);
      hub.select(SensorQuantity.heartRate, 'strap');
      expect(sensorGridHasContent(hub), isTrue);

      hub.unregister('strap');

      expect(sensorGridHasContent(hub), isFalse);
    });
  });

  testWidgets('speed never gets a cell — there is no real source behind it yet, even if one is connected and selected',
      (tester) async {
    final hub = SensorHub();
    final source = FakeSensorSource(id: 'spd', displayName: 'Speed sensor', provides: {SensorQuantity.speed});
    hub.register(source);
    hub.select(SensorQuantity.speed, 'spd');
    source.emit(SensorQuantity.speed, 32);

    await pumpGrid(tester, hub);

    expect(find.byKey(const Key('trainer-card-sensor-grid')), findsNothing);
    expect(find.byKey(const Key('trainer-card-sensor-cell-speed')), findsNothing);
  });
}
