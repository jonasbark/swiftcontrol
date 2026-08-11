import 'dart:convert';

import 'package:bike_control/main.dart' show recordError;
import 'package:bike_control/models/remembered_device.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Stores the devices the rider has actually connected to, so the home screen
/// can show them while they are switched off, out of range, or the app has just
/// been restarted.
///
/// Ordering is most-recently-connected first, which is also the order the home
/// screen renders offline cards in. The list is capped so a rider who has tried
/// a dozen loaner controllers doesn't accumulate a wall of ghosts.
class RememberedDevicesRepository {
  RememberedDevicesRepository(this._prefs);

  final SharedPreferences _prefs;

  static const String _key = 'remembered_devices';

  /// Enough for a Click V2 pair, a Play pair, a trainer and a couple of
  /// experiments; small enough that the list never becomes the screen.
  static const int maxEntries = 8;

  List<RememberedDevice> load() {
    final raw = _prefs.getString(_key);
    if (raw == null || raw.isEmpty) return [];

    final List<dynamic> entries;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      entries = decoded;
    } catch (e, s) {
      // A corrupt blob costs the rider their remembered list, but it must not
      // take the home screen down with it.
      recordError(e, s, context: 'RememberedDevicesRepository.load');
      return [];
    }

    final devices = <RememberedDevice>[];
    for (final entry in entries) {
      if (entry is! Map) continue;
      try {
        final device = RememberedDevice.tryFromJson(Map<String, dynamic>.from(entry));
        if (device != null) devices.add(device);
      } catch (e, s) {
        recordError(e, s, context: 'RememberedDevicesRepository.load entry');
      }
    }
    return devices;
  }

  /// Records a successful connection. Re-connecting a device already in the
  /// list refreshes its timestamp and moves it to the front rather than adding
  /// a duplicate.
  Future<void> remember(RememberedDevice device) async {
    final devices = load()..removeWhere((d) => d.deviceId == device.deviceId && d.kind == device.kind);
    devices.insert(0, device);
    await _save(devices.take(maxEntries).toList());
  }

  /// Drops an entry and returns the index it was at, so an Undo can put it
  /// back where the rider saw it. Returns null when nothing was removed.
  Future<int?> forget(String deviceId) async {
    final devices = load();
    final index = devices.indexWhere((d) => d.deviceId == deviceId);
    if (index == -1) return null;
    devices.removeAt(index);
    await _save(devices);
    return index;
  }

  /// Puts a forgotten entry back. [atIndex] is clamped, because the list may
  /// have changed (a device connected, another was forgotten) between the
  /// swipe and the Undo tap.
  Future<void> restore(RememberedDevice device, {int? atIndex}) async {
    final devices = load()..removeWhere((d) => d.deviceId == device.deviceId && d.kind == device.kind);
    final index = (atIndex ?? 0).clamp(0, devices.length);
    devices.insert(index, device);
    await _save(devices.take(maxEntries).toList());
  }

  Future<void> clear() => _prefs.remove(_key);

  Future<void> _save(List<RememberedDevice> devices) async {
    try {
      await _prefs.setString(_key, jsonEncode([for (final device in devices) device.toJson()]));
    } catch (e, s) {
      recordError(e, s, context: 'RememberedDevicesRepository.save');
    }
  }
}
