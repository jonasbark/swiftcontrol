import 'dart:async';

import 'package:flutter/foundation.dart';

import 'sensor_hub.dart';
import 'sensor_quantity.dart';
import 'sensor_sink_controller.dart';

/// Keeps a [SensorSinkController] in sync with two things: whether the
/// bridge is running, and whether the rider has selected a heart rate source
/// at all.
///
/// The second half matters on its own. Without it, BikeControl would start
/// advertising itself as a heart rate monitor the moment it launches — before
/// the rider has picked any source and with no reading to send. A monitor
/// that never reports a value reads as broken hardware, not as "nothing
/// chosen yet." Folding "no source selected" into the same `bridgeRunning`
/// flag the controller already understands — treat it as if the bridge WERE
/// running, so nothing standalone stands up — covers that with the flag the
/// controller already has, rather than adding a third state.
///
/// This also doubles as the retry path for a standalone start that failed at
/// launch (e.g. BLE permission not granted yet): [hub]'s
/// `onSelectionChanged` re-syncs on every selection change, not only on
/// bridge transitions, so picking (or re-picking) a source tries again.
///
/// Pulled out of `connection.dart` for the same reason [SensorSinkController]
/// and the binding it feeds are: that file cannot be constructed in a unit
/// test, and this rule is worth one.
class SensorSinkSync {
  SensorSinkSync({required this.hub, required this.isBridgeRunning, required this.sink});

  final SensorHub hub;
  final ValueListenable<bool> isBridgeRunning;
  final SensorSinkController sink;

  bool _started = false;

  /// Registers for bridge-state and selection-change updates and performs an
  /// initial sync. Idempotent.
  void start() {
    if (_started) return;
    _started = true;
    isBridgeRunning.addListener(sync);
    hub.onSelectionChanged = sync;
    unawaited(sync());
  }

  /// Recomputes the effective bridge state and applies it to [sink].
  ///
  /// Returns the `Future` (rather than being `void` and firing-and-forgetting
  /// internally) so a test can await one deterministic sync instead of
  /// pumping the event loop after [start].
  Future<void> sync() {
    final hasSource = hub.selectionFor(SensorQuantity.heartRate) != null;
    return sink.onBridgeStateChanged(bridgeRunning: isBridgeRunning.value || !hasSource);
  }

  void dispose() {
    if (!_started) return;
    isBridgeRunning.removeListener(sync);
    hub.onSelectionChanged = null;
    _started = false;
  }
}
