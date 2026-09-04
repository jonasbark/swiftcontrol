import 'package:bike_control/main.dart' show recordError;
import 'package:prop/emulators/definitions/sensor_definition.dart';

/// Where [SensorSinkController] should currently be serving [SensorDefinition]
/// from.
enum SensorSinkMode {
  /// Attached to the shared bridge composite.
  bridge,

  /// Served by its own standalone emulator.
  standalone,

  /// Attached nowhere — no source is selected, so there is nothing to serve.
  ///
  /// Deliberately distinct from [bridge] rather than folded into it: a
  /// [SensorDefinition] left attached to the bridge composite with nothing to
  /// publish keeps that composite's `children` non-empty forever, which stops
  /// the bridge's own "nothing is using me any more" shutdown check
  /// (`ProxyDevice._stopFtmsEmulatorIfUnused`) from ever firing — the bridge
  /// would keep advertising after the trainer disconnects. `none` genuinely
  /// detaches/stops, so an unrelated composite can tell it is truly unused.
  none,
}

/// Decides where the sensor services are served from.
///
/// There is one process-wide GATT server and one advertisement, so the sink
/// is never attached in two places at once: it rides the bridge's composite,
/// owns a standalone emulator, or — when nothing is selected — sits in
/// neither. Callbacks rather than concrete emulator types keep the decision
/// testable without a BLE stack.
class SensorSinkController {
  SensorSinkController({
    required this.definition,
    required this.attach,
    required this.detach,
    required this.startStandalone,
    required this.stopStandalone,
  });

  final SensorDefinition definition;
  final Future<void> Function(SensorDefinition) attach;
  final Future<void> Function(SensorDefinition) detach;
  final Future<void> Function(SensorDefinition) startStandalone;
  final Future<void> Function() stopStandalone;

  bool _attached = false;
  bool _standalone = false;
  SensorSinkMode? _lastMode;

  /// Serialises transitions. Sink state flaps, and a second call arriving
  /// while the first is suspended at an `await` would sail past the
  /// idempotency guard — leaving the sink attached AND standalone, which is
  /// the one thing this class exists to prevent.
  Future<void> _inFlight = Future<void>.value();

  bool get attachedToComposite => _attached;
  bool get standaloneRunning => _standalone;

  Future<void> onSinkStateChanged({required SensorSinkMode mode}) {
    _inFlight = _inFlight.then((_) => _apply(mode));
    return _inFlight;
  }

  Future<void> _apply(SensorSinkMode mode) async {
    if (_lastMode == mode) return;
    // Entering a transition means there is no known-good state any more: the
    // branches below mutate (`detach`, `_attached = false`) BEFORE the fallible
    // await, so a throw can leave the sink half torn down. Nulling the guard
    // here means any later call — for any target — retries instead of being
    // swallowed as a no-op and leaving the sink served nowhere.
    _lastMode = null;
    try {
      if (mode == SensorSinkMode.bridge) {
        if (_standalone) {
          await stopStandalone();
          _standalone = false;
        }
        await attach(definition);
        _attached = true;
      } else if (mode == SensorSinkMode.standalone) {
        if (_attached) {
          await detach(definition);
          _attached = false;
        }
        await startStandalone(definition);
        _standalone = true;
      } else {
        // SensorSinkMode.none: served nowhere.
        if (_attached) {
          await detach(definition);
          _attached = false;
        }
        if (_standalone) {
          await stopStandalone();
          _standalone = false;
        }
      }
      _lastMode = mode;
    } catch (e, s) {
      await recordError(e, s, context: 'SensorSinkController');
    }
  }
}
