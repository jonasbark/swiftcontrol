import 'package:flutter/foundation.dart';

import 'sensor_quantity.dart';
import 'sensor_reading.dart';

/// A producer of rider metrics that is not the trainer.
///
/// Implementations own transport and parsing only. Selection, staleness and
/// fallback are the hub's business — see `SensorHub`.
abstract class SensorSource {
  /// Stable across restarts; persisted as the rider's per-quantity choice.
  String get id;

  String get displayName;

  Set<SensorQuantity> get provides;

  ValueListenable<SensorReading?> readingFor(SensorQuantity quantity);

  Future<void> start();

  Future<void> stop();
}
