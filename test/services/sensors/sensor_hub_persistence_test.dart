import 'package:bike_control/services/sensors/fake_sensor_source.dart';
import 'package:bike_control/services/sensors/sensor_hub.dart';
import 'package:bike_control/services/sensors/sensor_quantity.dart';
import 'package:bike_control/utils/settings/settings.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('a selection survives a hub restart', () async {
    final settings = Settings()..prefs = await SharedPreferences.getInstance();

    final first = SensorHub();
    first.register(FakeSensorSource(
      id: 'strap',
      displayName: 'Strap',
      provides: {SensorQuantity.heartRate},
    ));
    first.select(SensorQuantity.heartRate, 'strap');
    await first.persistSelections(settings);

    final second = SensorHub();
    second.register(FakeSensorSource(
      id: 'strap',
      displayName: 'Strap',
      provides: {SensorQuantity.heartRate},
    ));
    second.loadSelections(settings);

    expect(second.selectionFor(SensorQuantity.heartRate), 'strap');
  });

  test('a persisted source that is no longer present degrades to the trainer', () async {
    final settings = Settings()..prefs = await SharedPreferences.getInstance();
    await settings.setSensorSelection(SensorQuantity.heartRate.name, 'ghost');

    final hub = SensorHub();
    hub.loadSelections(settings);

    expect(hub.selectionFor(SensorQuantity.heartRate), isNull);
    expect(hub.resolved(SensorQuantity.heartRate).value, isNull);
  });

  test('a restored-but-missing source leaves droppedOut false', () async {
    final settings = Settings()..prefs = await SharedPreferences.getInstance();
    await settings.setSensorSelection(SensorQuantity.heartRate.name, 'ghost');

    final hub = SensorHub();
    hub.loadSelections(settings);

    expect(hub.droppedOut(SensorQuantity.heartRate).value, isFalse);
  });
}
