import 'dart:typed_data';

import 'package:flutter/foundation.dart';

/// Decodes an mDNS TXT value for display: printable ASCII is kept as-is,
/// anything else (e.g. a version byte `0x01`) renders as a `0x…` hex preview.
String decodeMdnsTxt(List<int> bytes) {
  final s = String.fromCharCodes(bytes);
  if (s.runes.every((r) => r >= 0x20 && r < 0x7f)) return s;
  return '0x${bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join()}';
}

/// One live mDNS advertisement, captured for diagnostics.
class AdvertisedRecord {
  final String name;
  final String type;
  final int port;
  final String address;
  final Map<String, String> txt;

  const AdvertisedRecord({
    required this.name,
    required this.type,
    required this.port,
    required this.address,
    required this.txt,
  });
}

/// Process-wide list of what this app currently advertises over mDNS, so the
/// Logs page / debugText can show it.
class AdvertisedServiceRegistry {
  AdvertisedServiceRegistry._();
  static final AdvertisedServiceRegistry instance = AdvertisedServiceRegistry._();

  final _records = <AdvertisedRecord>[];

  List<AdvertisedRecord> get records => List.unmodifiable(_records);

  AdvertisedRecord add({
    required String name,
    required String type,
    required int port,
    required String address,
    required Map<String, Uint8List> txt,
  }) {
    final record = AdvertisedRecord(
      name: name,
      type: type,
      port: port,
      address: address,
      txt: txt.map((k, v) => MapEntry(k, decodeMdnsTxt(v))),
    );
    _records.add(record);
    return record;
  }

  void remove(AdvertisedRecord record) => _records.remove(record);

  @visibleForTesting
  void clear() => _records.clear();
}
