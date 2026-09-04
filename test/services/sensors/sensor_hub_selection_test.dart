import 'package:bike_control/services/sensors/fake_sensor_source.dart';
import 'package:bike_control/services/sensors/sensor_hub.dart';
import 'package:bike_control/services/sensors/sensor_quantity.dart';
import 'package:flutter_test/flutter_test.dart';

FakeSensorSource _hrSource(String id) => FakeSensorSource(
  id: id,
  displayName: 'Strap $id',
  provides: {SensorQuantity.heartRate},
);

void main() {
  test('defaults to the trainer, so resolved() is null', () {
    final hub = SensorHub();
    hub.register(_hrSource('a'));

    expect(hub.selectionFor(SensorQuantity.heartRate), isNull);
    expect(hub.resolved(SensorQuantity.heartRate).value, isNull);
  });

  test('a selected source publishes its value', () {
    final hub = SensorHub();
    final source = _hrSource('a');
    hub.register(source);
    hub.select(SensorQuantity.heartRate, 'a');

    source.emit(SensorQuantity.heartRate, 155);

    expect(hub.resolved(SensorQuantity.heartRate).value, 155);
  });

  test('reselecting the trainer drops back to null', () {
    final hub = SensorHub();
    final source = _hrSource('a');
    hub.register(source);
    hub.select(SensorQuantity.heartRate, 'a');
    source.emit(SensorQuantity.heartRate, 155);

    hub.select(SensorQuantity.heartRate, null);

    expect(hub.resolved(SensorQuantity.heartRate).value, isNull);
  });

  test('sourcesFor only offers sources providing that quantity', () {
    final hub = SensorHub();
    hub.register(_hrSource('a'));
    hub.register(FakeSensorSource(
      id: 'p',
      displayName: 'Meter',
      provides: {SensorQuantity.power},
    ));

    expect(hub.sourcesFor(SensorQuantity.heartRate).map((s) => s.id), ['a']);
    expect(hub.sourcesFor(SensorQuantity.power).map((s) => s.id), ['p']);
  });

  test('unregistering the selected source falls back to the trainer', () {
    final hub = SensorHub();
    final source = _hrSource('a');
    hub.register(source);
    hub.select(SensorQuantity.heartRate, 'a');
    source.emit(SensorQuantity.heartRate, 155);

    hub.unregister('a');

    expect(hub.selectionFor(SensorQuantity.heartRate), isNull);
    expect(hub.resolved(SensorQuantity.heartRate).value, isNull);
  });
}
