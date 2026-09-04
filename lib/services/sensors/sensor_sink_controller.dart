import 'package:bike_control/main.dart' show recordError;
import 'package:prop/emulators/definitions/sensor_definition.dart';

/// Decides where the sensor services are served from.
///
/// There is one process-wide GATT server and one advertisement, so the sink is
/// never two Bluetooth devices at once: either the definition rides the
/// bridge's composite, or it owns a standalone emulator. Callbacks rather than
/// concrete emulator types keep the decision testable without a BLE stack.
class SensorSinkController {
  SensorSinkController({
    required this.definition,
    required this.attach,
    required this.detach,
    required this.startStandalone,
    required this.stopStandalone,
  });

  final SensorDefinition definition;
  final void Function(SensorDefinition) attach;
  final void Function(SensorDefinition) detach;
  final Future<void> Function(SensorDefinition) startStandalone;
  final Future<void> Function() stopStandalone;

  bool _attached = false;
  bool _standalone = false;
  bool? _lastBridgeRunning;

  /// Serialises transitions. Bridge state flaps, and a second call arriving
  /// while the first is suspended at an `await` would sail past the
  /// idempotency guard — leaving the sink attached AND standalone, which is
  /// the one thing this class exists to prevent.
  Future<void> _inFlight = Future<void>.value();

  bool get attachedToComposite => _attached;
  bool get standaloneRunning => _standalone;

  Future<void> onBridgeStateChanged({required bool bridgeRunning}) {
    _inFlight = _inFlight.then((_) => _apply(bridgeRunning));
    return _inFlight;
  }

  Future<void> _apply(bool bridgeRunning) async {
    if (_lastBridgeRunning == bridgeRunning) return;
    try {
      if (bridgeRunning) {
        if (_standalone) {
          await stopStandalone();
          _standalone = false;
        }
        attach(definition);
        _attached = true;
      } else {
        if (_attached) {
          detach(definition);
          _attached = false;
        }
        await startStandalone(definition);
        _standalone = true;
      }
      _lastBridgeRunning = bridgeRunning;
    } catch (e, s) {
      await recordError(e, s, context: 'SensorSinkController');
    }
  }
}
