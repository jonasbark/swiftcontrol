import 'package:flutter/foundation.dart';

import 'sensor_quantity.dart';
import 'sensor_reading.dart';
import 'sensor_source.dart';

/// A standards-compliant BLE sensor paired directly to BikeControl.
///
/// Parsing only. The transport (connect, subscribe, reconnect) is the
/// `BleHeartRateDevice` half; everything above this is the hub's business.
class BleSensorSource extends SensorSource {
  BleSensorSource({
    required this.id,
    required this.displayName,
    required this.provides,
  });

  static const heartRateServiceUuid = '0000180d-0000-1000-8000-00805f9b34fb';
  static const heartRateMeasurementUuid = '00002a37-0000-1000-8000-00805f9b34fb';

  @override
  final String id;

  @override
  final String displayName;

  @override
  final Set<SensorQuantity> provides;

  final Map<SensorQuantity, ValueNotifier<SensorReading?>> _readings = {};

  @override
  ValueListenable<SensorReading?> readingFor(SensorQuantity quantity) =>
      _notifierFor(quantity);

  ValueNotifier<SensorReading?> _notifierFor(SensorQuantity quantity) =>
      _readings.putIfAbsent(quantity, () => ValueNotifier<SensorReading?>(null));

  /// Heart Rate Measurement (0x2A37). Bit 0 of the flags byte selects uint16
  /// over uint8. A short frame is dropped rather than guessed at: a wrong
  /// heart rate is worse than none.
  @visibleForTesting
  void ingestHeartRateMeasurement(List<int> bytes, {DateTime? at}) {
    if (bytes.length < 2) return;
    final is16Bit = (bytes[0] & 0x01) != 0;
    if (is16Bit && bytes.length < 3) return;
    final bpm = is16Bit ? (bytes[1] | (bytes[2] << 8)) : bytes[1];
    _notifierFor(SensorQuantity.heartRate).value =
        SensorReading(bpm, at ?? DateTime.now());
  }

  @override
  Future<void> start() async {}

  @override
  Future<void> stop() async {
    for (final notifier in _readings.values) {
      notifier.value = null;
    }
  }
}
