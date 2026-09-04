import 'dart:async';

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

  test('concurrent calls are serialized to maintain invariant', () async {
    late Completer<void> startCompleter;

    controller = SensorSinkController(
      definition: SensorDefinition(),
      attach: (_) => calls.add('attach'),
      detach: (_) => calls.add('detach'),
      startStandalone: (_) async {
        startCompleter = Completer<void>();
        calls.add('start');
        await startCompleter.future;
      },
      stopStandalone: () async => calls.add('stop'),
    );

    // Start a call to bridge=false (will suspend at startStandalone)
    final future1 = controller.onBridgeStateChanged(bridgeRunning: false);

    // Let it reach the await point
    await Future.delayed(Duration(milliseconds: 100));

    // While suspended, call with bridge=true
    final future2 = controller.onBridgeStateChanged(bridgeRunning: true);

    // Resume the first call
    startCompleter.complete();

    // Wait for both to finish
    await future1;
    await future2;

    // The invariant: never both attached AND standalone
    expect(controller.attachedToComposite && controller.standaloneRunning, isFalse);

    // Call sequence should be legal: either bridge→standalone or standalone→bridge
    // With the fix, we expect: detach, start, stop, attach (two transitions)
    // Without serialization, we might get: detach, attach, start (broken)
    expect(calls.contains('attach'), isTrue);
    expect(calls.contains('start'), isTrue);
  });

  test('failed transition is retried on next call with same state', () async {
    int startAttempts = 0;

    controller = SensorSinkController(
      definition: SensorDefinition(),
      attach: (_) => calls.add('attach'),
      detach: (_) => calls.add('detach'),
      startStandalone: (_) async {
        startAttempts++;
        if (startAttempts == 1) {
          calls.add('start-fail');
          throw Exception('Simulated failure');
        }
        calls.add('start-success');
      },
      stopStandalone: () async => calls.add('stop'),
    );

    // First call fails
    try {
      await controller.onBridgeStateChanged(bridgeRunning: false);
    } catch (_) {
      // Exception is caught and recorded by recordError
    }

    // Controller should still be in the old state; the sink is served NOWHERE
    expect(controller.standaloneRunning, isFalse);
    expect(controller.attachedToComposite, isFalse);

    // Reset the mock
    calls.clear();

    // Second call with the SAME state should retry
    try {
      await controller.onBridgeStateChanged(bridgeRunning: false);
    } catch (_) {}

    // This time it should succeed
    expect(startAttempts, 2); // Both attempts were made
    expect(controller.standaloneRunning, isTrue);
    expect(calls.contains('start-success'), isTrue);
  });

  test('failed transition to standalone does not strand when attaching after',
      () async {
    int attemptCount = 0;

    controller = SensorSinkController(
      definition: SensorDefinition(),
      attach: (_) => calls.add('attach'),
      detach: (_) => calls.add('detach'),
      startStandalone: (_) async {
        attemptCount++;
        if (attemptCount == 1) {
          calls.add('start-fail');
          throw Exception('Standalone startup failed');
        }
        calls.add('start-success');
      },
      stopStandalone: () async => calls.add('stop'),
    );

    // Transition to attached (this succeeds and sets _lastBridgeRunning = true)
    await controller.onBridgeStateChanged(bridgeRunning: true);
    expect(controller.attachedToComposite, isTrue);
    calls.clear();

    // Attempt transition to standalone: startStandalone throws
    // Without the fix: _lastBridgeRunning is still 'true' after the exception
    // because the assignment was at the end of try and never reached.
    // With the fix: _lastBridgeRunning is null because it's set on entry.
    try {
      await controller.onBridgeStateChanged(bridgeRunning: false);
    } catch (_) {}

    expect(controller.attachedToComposite, isFalse);
    expect(controller.standaloneRunning, isFalse);
    calls.clear();

    // Now attempt to re-attach. Without the fix, _lastBridgeRunning is still
    // 'true' from the original attach, so the guard check `if (_lastBridgeRunning
    // == bridgeRunning) return` silently no-ops and attach never runs, leaving
    // the sink stranded. With the fix, _lastBridgeRunning is null, so the guard
    // passes and attach runs.
    await controller.onBridgeStateChanged(bridgeRunning: true);

    expect(calls, contains('attach'));
    expect(controller.attachedToComposite, isTrue);
  });
}
