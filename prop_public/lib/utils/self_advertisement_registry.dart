import 'package:flutter/foundation.dart';

/// Tracks every mDNS service this process is currently advertising so the
/// WiFi trainer scanner can exclude our own advertisements.
class SelfAdvertisementRegistry {
  SelfAdvertisementRegistry._();
  static final SelfAdvertisementRegistry instance = SelfAdvertisementRegistry._();

  final _entries = <({String name, int port})>{};

  void add({required String name, required int port}) => _entries.add((name: name, port: port));
  void remove({required String name, required int port}) => _entries.remove((name: name, port: port));

  bool containsName(String name) => _entries.any((e) => e.name == name);
  bool containsPort(int port) => _entries.any((e) => e.port == port);

  @visibleForTesting
  void clear() => _entries.clear();
}
