import 'package:bike_control/services/sensors/fake_sensor_source.dart';
import 'package:bike_control/services/sensors/sensor_hub.dart';
import 'package:bike_control/services/sensors/sensor_quantity.dart';
import 'package:bike_control/services/sensors/sensor_sink_controller.dart';
import 'package:bike_control/services/sensors/sensor_sink_sync.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prop/emulators/definitions/sensor_definition.dart';

void main() {
  late List<String> calls;
  late SensorHub hub;
  late ValueNotifier<bool> isBridgeRunning;
  late SensorSinkController sink;
  late SensorSinkSync sync;

  setUp(() {
    calls = [];
    hub = SensorHub();
    isBridgeRunning = ValueNotifier<bool>(false);
    sink = SensorSinkController(
      definition: SensorDefinition(),
      attach: (_) async => calls.add('attach'),
      detach: (_) async => calls.add('detach'),
      startStandalone: (_) async => calls.add('start'),
      stopStandalone: () async => calls.add('stop'),
    );
    sync = SensorSinkSync(hub: hub, isBridgeRunning: isBridgeRunning, sink: sink);
  });

  tearDown(() => sync.dispose());

  // "No source" is folded into `bridgeRunning` (see SensorSinkSync's doc
  // comment), so the sink rides the — not-yet-advertising — bridge composite
  // instead of doing nothing: attach() runs, but startStandalone() must not.
  test('with no source selected, no standalone start is attempted at all', () async {
    await sync.sync();

    expect(calls, isNot(contains('start')));
    expect(sink.standaloneRunning, isFalse);
    expect(sink.attachedToComposite, isTrue);
  });

  test('a selected source starts the standalone sink when the bridge is not running', () async {
    final source = FakeSensorSource(id: 'strap', displayName: 'Strap', provides: {SensorQuantity.heartRate});
    hub.register(source);
    hub.select(SensorQuantity.heartRate, 'strap');

    await sync.sync();

    expect(calls, ['start']);
    expect(sink.standaloneRunning, isTrue);
  });

  test('the bridge running takes precedence even with a source selected', () async {
    final source = FakeSensorSource(id: 'strap', displayName: 'Strap', provides: {SensorQuantity.heartRate});
    hub.register(source);
    hub.select(SensorQuantity.heartRate, 'strap');
    isBridgeRunning.value = true;

    await sync.sync();

    expect(calls, ['attach']);
    expect(sink.attachedToComposite, isTrue);
  });

  test('start() re-syncs automatically when a source is selected afterwards', () async {
    sync.start();
    // Settle the initial sync triggered by start(): cold start, no source,
    // so it rides the bridge composite (attach), not standalone.
    await Future<void>.delayed(Duration.zero);
    expect(calls, ['attach']);
    calls.clear();

    final source = FakeSensorSource(id: 'strap', displayName: 'Strap', provides: {SensorQuantity.heartRate});
    hub.register(source);
    hub.select(SensorQuantity.heartRate, 'strap');
    // select() invokes the onSelectionChanged hook synchronously; let the
    // resulting onBridgeStateChanged transition settle.
    await Future<void>.delayed(Duration.zero);

    expect(calls, ['detach', 'start']);
    expect(sink.standaloneRunning, isTrue);
  });

  test('dispose stops re-syncing on selection changes', () async {
    sync.start();
    await Future<void>.delayed(Duration.zero);
    sync.dispose();
    calls.clear();

    final source = FakeSensorSource(id: 'strap', displayName: 'Strap', provides: {SensorQuantity.heartRate});
    hub.register(source);
    hub.select(SensorQuantity.heartRate, 'strap');
    await Future<void>.delayed(Duration.zero);

    expect(calls, isEmpty);
  });
}
