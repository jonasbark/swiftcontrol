import 'package:flutter/foundation.dart';

import 'package:bike_control/bluetooth/support_log_buffer.dart';
import 'package:bike_control/utils/settings/settings.dart';

import 'sensor_quantity.dart';
import 'sensor_source.dart';

/// Owns every decision about where a rider metric comes from.
///
/// `prop` deliberately knows none of this: the hub publishes a resolved value
/// per quantity, or `null` meaning "trainer, use your own". Keeping the policy
/// here is what makes it testable without any of the hardware it supports.
class SensorHub {
  SensorHub({DateTime Function()? now, this.log}) : _now = now ?? DateTime.now;

  /// TUNABLE. BLE heart rate / CSC / power sensors notify at about 1 Hz.
  static const bleSensorTtl = Duration(seconds: 5);

  /// TUNABLE. HealthKit passive delivery is batched and can lag far behind a
  /// BLE strap; a 5 s window here would flap continuously.
  static const healthKitTtl = Duration(seconds: 30);

  final DateTime Function() _now;

  /// Attached during wiring rather than construction: the buffer lives on
  /// `Connection`, which is built after `core`.
  SupportLogBuffer? log;

  final Map<String, SensorSource> _sources = {};
  final Map<SensorQuantity, String?> _selection = {};
  final Map<SensorQuantity, ValueNotifier<int?>> _resolved = {};
  final Map<SensorQuantity, ValueNotifier<bool>> _droppedOut = {};
  final Map<SensorQuantity, VoidCallback> _listeners = {};

  List<SensorSource> get sources => List.unmodifiable(_sources.values);

  void register(SensorSource source) {
    _sources[source.id] = source;
  }

  void unregister(String id) {
    // Drop the selection BEFORE removing the source: `select` detaches the
    // listener by looking the current source up, so removing it first would
    // strand the listener on a notifier nothing ever cleans up.
    for (final quantity in SensorQuantity.values) {
      if (_selection[quantity] == id) select(quantity, null);
    }
    _sources.remove(id);
  }

  List<SensorSource> sourcesFor(SensorQuantity quantity) =>
      _sources.values.where((s) => s.provides.contains(quantity)).toList();

  String? selectionFor(SensorQuantity quantity) => _selection[quantity];

  ValueListenable<int?> resolved(SensorQuantity quantity) => _resolvedNotifier(quantity);

  ValueNotifier<int?> _resolvedNotifier(SensorQuantity quantity) =>
      _resolved.putIfAbsent(quantity, () => ValueNotifier<int?>(null));

  ValueListenable<bool> droppedOut(SensorQuantity quantity) => _droppedOutNotifier(quantity);

  ValueNotifier<bool> _droppedOutNotifier(SensorQuantity quantity) =>
      _droppedOut.putIfAbsent(quantity, () => ValueNotifier<bool>(false));

  /// Re-evaluates freshness for every quantity. Called on a timer by the
  /// owner and directly by tests.
  void tick() {
    for (final quantity in SensorQuantity.values) {
      if (_selection[quantity] != null) _publish(quantity);
    }
  }

  void select(SensorQuantity quantity, String? sourceId) {
    _detachListener(quantity);
    _selection[quantity] = sourceId;

    if (sourceId == null) {
      _resolvedNotifier(quantity).value = null;
      // The trainer cannot drop out.
      _droppedOutNotifier(quantity).value = false;
      return;
    }

    final source = _sources[sourceId];
    if (source == null) {
      _selection[quantity] = null;
      _resolvedNotifier(quantity).value = null;
      // A persisted source id that no longer resolves should not leave the
      // drop-out flag stuck from a previous session.
      _droppedOutNotifier(quantity).value = false;
      return;
    }

    final reading = source.readingFor(quantity);
    void listener() => _publish(quantity);
    reading.addListener(listener);
    _listeners[quantity] = listener;
    _publish(quantity);
  }

  void _publish(SensorQuantity quantity) {
    final sourceId = _selection[quantity];
    final source = sourceId == null ? null : _sources[sourceId];
    final reading = source?.readingFor(quantity).value;

    final stale = reading == null || _now().difference(reading.timestamp) > (source?.ttl ?? bleSensorTtl);

    final wasDropped = _droppedOutNotifier(quantity).value;
    if (stale && !wasDropped && reading != null) {
      log?.add('sensor drop-out: ${source?.displayName} for ${quantity.name}');
    }
    _droppedOutNotifier(quantity).value = stale;

    // `null` hands the quantity back to the trainer; in standalone mode it
    // simply means there is no value to notify.
    _resolvedNotifier(quantity).value = stale ? null : reading.value;
  }

  void _detachListener(SensorQuantity quantity) {
    final listener = _listeners.remove(quantity);
    if (listener == null) return;
    final previousId = _selection[quantity];
    final previous = previousId == null ? null : _sources[previousId];
    previous?.readingFor(quantity).removeListener(listener);
  }

  void dispose() {
    for (final quantity in SensorQuantity.values) {
      _detachListener(quantity);
    }
    for (final notifier in _resolved.values) {
      notifier.dispose();
    }
    _resolved.clear();
    for (final notifier in _droppedOut.values) {
      notifier.dispose();
    }
    _droppedOut.clear();
  }

  /// Restores persisted selections. A stored id with no registered source
  /// silently becomes "trainer" — `select` already handles that case.
  void loadSelections(Settings settings) {
    for (final quantity in SensorQuantity.values) {
      select(quantity, settings.getSensorSelection(quantity.name));
    }
  }

  Future<void> persistSelections(Settings settings) async {
    for (final quantity in SensorQuantity.values) {
      await settings.setSensorSelection(quantity.name, _selection[quantity]);
    }
  }
}
