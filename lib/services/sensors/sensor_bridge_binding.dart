import 'package:flutter/foundation.dart';

import 'sensor_hub.dart';
import 'sensor_quantity.dart';

/// Forwards the hub's resolved values to whatever is serving them.
///
/// `null` is meaningful and must be forwarded: it is how the bridge is told to
/// go back to the trainer's own reading after a sensor drops out.
class SensorBridgeBinding {
  SensorBridgeBinding({required this.hub, required this.onHeartRate});

  final SensorHub hub;
  final void Function(int?) onHeartRate;

  ValueListenable<int?>? _heartRate;
  VoidCallback? _listener;

  void start() {
    final heartRate = hub.resolved(SensorQuantity.heartRate);
    void listener() => onHeartRate(heartRate.value);
    heartRate.addListener(listener);
    _heartRate = heartRate;
    _listener = listener;
    listener();
  }

  void dispose() {
    final listener = _listener;
    if (listener != null) _heartRate?.removeListener(listener);
    _listener = null;
    _heartRate = null;
  }
}
