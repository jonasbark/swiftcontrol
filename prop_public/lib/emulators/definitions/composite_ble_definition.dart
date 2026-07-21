//INFO: This is a stub - contact me if you need the full implementation.
//
// The full implementation aggregates child definitions and routes dispatch by
// service / characteristic UUID. This stub keeps the child bookkeeping the app
// reads and stubs the routing.

import 'package:flutter/foundation.dart';
import 'package:prop/emulators/ble_definition.dart';
import 'package:universal_ble/universal_ble.dart';

class CompositeBleDefinition extends BleDefinition {
  CompositeBleDefinition({List<BleDefinition> initial = const []}) {
    _children.addAll(initial);
  }

  final List<BleDefinition> _children = [];

  /// Read-only view of the currently attached children, in attach-order.
  List<BleDefinition> get children => List.unmodifiable(_children);

  /// Attach [def] as a new child. Returns `true` if it was newly added.
  bool attach(BleDefinition def) {
    if (_children.contains(def)) return false;
    _children.add(def);
    return true;
  }

  /// Detach [def]. Returns `true` if [def] was a current child.
  bool detach(BleDefinition def) => _children.remove(def);

  /// First child whose runtime type is [T], or `null` if none.
  T? firstOfType<T extends BleDefinition>() {
    for (final c in _children) {
      if (c is T) return c;
    }
    return null;
  }

  @override
  List<String> get serviceUUIDs => const [];

  @override
  List<String> get advertiseServiceUUIDs => const [];

  @override
  List<BleCharacteristic> getCharacteristics(String serviceUUID) => const [];

  @override
  void onWriteRequest(String characteristicUUID, List<int> characteristicData) {}

  @override
  void onNotification(String characteristic, Uint8List bytes) {}
}
