import 'package:bike_control/services/sensors/sensor_sink_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prop/emulators/definitions/sensor_definition.dart';

void main() {
  late List<String> calls;
  late SensorSinkController controller;

  setUp(() {
    calls = [];
    controller = SensorSinkController(
      definition: SensorDefinition(),
      attach: (_) => calls.add('attach'),
      detach: (_) => calls.add('detach'),
      startStandalone: (_) async => calls.add('start'),
      stopStandalone: () async => calls.add('stop'),
    );
  });

  test('attaches to the composite while a bridge is running', () async {
    await controller.onBridgeStateChanged(bridgeRunning: true);

    expect(controller.attachedToComposite, isTrue);
    expect(controller.standaloneRunning, isFalse);
    expect(calls, ['attach']);
  });

  test('starts a standalone emulator when no bridge is running', () async {
    await controller.onBridgeStateChanged(bridgeRunning: false);

    expect(controller.standaloneRunning, isTrue);
    expect(controller.attachedToComposite, isFalse);
    expect(calls, ['start']);
  });

  test('a transition detaches before starting, never running both', () async {
    await controller.onBridgeStateChanged(bridgeRunning: true);
    calls.clear();

    await controller.onBridgeStateChanged(bridgeRunning: false);

    expect(calls, ['detach', 'start']);
    expect(controller.attachedToComposite, isFalse);
    expect(controller.standaloneRunning, isTrue);
  });

  test('a transition back to bridging stops the standalone emulator first', () async {
    await controller.onBridgeStateChanged(bridgeRunning: false);
    calls.clear();

    await controller.onBridgeStateChanged(bridgeRunning: true);

    expect(calls, ['stop', 'attach']);
    expect(controller.standaloneRunning, isFalse);
    expect(controller.attachedToComposite, isTrue);
  });

  test('repeating the same state is idempotent', () async {
    await controller.onBridgeStateChanged(bridgeRunning: true);
    calls.clear();

    await controller.onBridgeStateChanged(bridgeRunning: true);

    expect(calls, isEmpty);
  });
}
