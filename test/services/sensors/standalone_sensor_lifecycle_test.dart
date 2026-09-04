import 'package:bike_control/services/sensors/standalone_sensor_lifecycle.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prop/emulators/definitions/sensor_definition.dart';

void main() {
  late List<String> calls;
  late StandaloneSensorLifecycle lifecycle;

  setUp(() {
    calls = [];
    lifecycle = StandaloneSensorLifecycle(
      attachDefinition: (_) async => calls.add('attach'),
      startServer: () async => calls.add('start'),
      stopServer: () async => calls.add('stop'),
      detachDefinition: (_) async => calls.add('detach'),
    );
  });

  test('start attaches the definition before starting the server', () async {
    await lifecycle.start(SensorDefinition());

    expect(calls, ['attach', 'start']);
  });

  test('stop stops the server before detaching the definition', () async {
    await lifecycle.stop(SensorDefinition());

    expect(calls, ['stop', 'detach']);
  });
}
