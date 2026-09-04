import 'package:bike_control/services/sensors/fake_sensor_source.dart';
import 'package:bike_control/services/sensors/sensor_bridge_binding.dart';
import 'package:bike_control/services/sensors/sensor_hub.dart';
import 'package:bike_control/services/sensors/sensor_quantity.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late DateTime clock;
  late SensorHub hub;
  late FakeSensorSource source;
  late List<int?> pushed;
  late SensorBridgeBinding binding;

  setUp(() {
    clock = DateTime.utc(2026, 9, 4, 12);
    hub = SensorHub(now: () => clock);
    source = FakeSensorSource(
      id: 'strap',
      displayName: 'Strap',
      provides: {SensorQuantity.heartRate},
    );
    hub.register(source);
    hub.select(SensorQuantity.heartRate, 'strap');
    pushed = [];
    binding = SensorBridgeBinding(hub: hub, onHeartRate: pushed.add)..start();
  });

  tearDown(() => binding.dispose());

  test('a resolved heart rate is pushed to the sink', () {
    source.emit(SensorQuantity.heartRate, 150, at: clock);

    expect(pushed.last, 150);
  });

  test('a drop-out pushes null so the trainer takes back over', () {
    source.emit(SensorQuantity.heartRate, 150, at: clock);
    clock = clock.add(const Duration(seconds: 6));
    hub.tick();

    expect(pushed.last, isNull);
  });

  test('dispose stops further pushes', () {
    binding.dispose();
    pushed.clear();

    source.emit(SensorQuantity.heartRate, 150, at: clock);

    expect(pushed, isEmpty);
  });
}
