import 'package:flutter/foundation.dart';

import 'sensor_quantity.dart';
import 'sensor_source.dart';

/// Owns every decision about where a rider metric comes from.
///
/// `prop` deliberately knows none of this: the hub publishes a resolved value
/// per quantity, or `null` meaning "trainer, use your own". Keeping the policy
/// here is what makes it testable without any of the hardware it supports.
class SensorHub {
  final Map<String, SensorSource> _sources = {};
  final Map<SensorQuantity, String?> _selection = {};
  final Map<SensorQuantity, ValueNotifier<int?>> _resolved = {};
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

  ValueListenable<int?> resolved(SensorQuantity quantity) =>
      _resolvedNotifier(quantity);

  ValueNotifier<int?> _resolvedNotifier(SensorQuantity quantity) =>
      _resolved.putIfAbsent(quantity, () => ValueNotifier<int?>(null));

  void select(SensorQuantity quantity, String? sourceId) {
    _detachListener(quantity);
    _selection[quantity] = sourceId;

    if (sourceId == null) {
      _resolvedNotifier(quantity).value = null;
      return;
    }

    final source = _sources[sourceId];
    if (source == null) {
      _selection[quantity] = null;
      _resolvedNotifier(quantity).value = null;
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
    _resolvedNotifier(quantity).value =
        source?.readingFor(quantity).value?.value;
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
  }
}
