import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:universal_ble/universal_ble.dart';

/// What a remembered entry stands in for on the home screen.
enum RememberedDeviceKind { controller, trainer }

/// A snapshot of a device we have successfully connected to before.
///
/// Without this, a controller that is switched off or out of range disappears
/// from the app completely: the rider can't see what they own, can't tell
/// "never set up" from "not here right now", and can't change a button mapping
/// away from the bike.
///
/// The snapshot deliberately stores exactly the fields
/// [BluetoothDevice.fromScanResult] reads — id, name, advertised services and
/// manufacturer data. That means a remembered entry rebuilds into a *real*
/// device object of the right subclass, with its real `availableButtons` and
/// `controllerLayout`, instead of a hand-rolled approximation that would drift
/// from the hardware definitions.
@immutable
class RememberedDevice {
  const RememberedDevice({
    required this.deviceId,
    required this.name,
    required this.kind,
    required this.lastConnected,
    this.services = const [],
    this.manufacturerData = const [],
  });

  final String deviceId;
  final String? name;
  final RememberedDeviceKind kind;
  final DateTime lastConnected;
  final List<String> services;
  final List<ManufacturerData> manufacturerData;

  /// Captures a live device's advertisement so it can be rebuilt later.
  factory RememberedDevice.fromScanResult(
    BleDevice scanResult, {
    required RememberedDeviceKind kind,
    required DateTime lastConnected,
  }) {
    return RememberedDevice(
      deviceId: scanResult.deviceId,
      // `rawName` is what the platform actually advertised; `name` is the
      // sanitized version. Keep the raw one so the rebuilt BleDevice sanitizes
      // it identically rather than sanitizing twice.
      name: scanResult.rawName ?? scanResult.name,
      kind: kind,
      lastConnected: lastConnected,
      services: List<String>.from(scanResult.services),
      manufacturerData: List<ManufacturerData>.from(scanResult.manufacturerDataList),
    );
  }

  /// Rebuilds the advertisement. `rssi` is deliberately null: we have not
  /// heard from this device in this session and must not pretend otherwise.
  BleDevice toScanResult() {
    return BleDevice(
      deviceId: deviceId,
      name: name,
      services: services,
      manufacturerDataList: manufacturerData,
    );
  }

  RememberedDevice copyWith({DateTime? lastConnected}) {
    return RememberedDevice(
      deviceId: deviceId,
      name: name,
      kind: kind,
      lastConnected: lastConnected ?? this.lastConnected,
      services: services,
      manufacturerData: manufacturerData,
    );
  }

  Map<String, dynamic> toJson() => {
    'deviceId': deviceId,
    'name': name,
    'kind': kind.name,
    'lastConnected': lastConnected.toIso8601String(),
    'services': services,
    'manufacturerData': [
      for (final data in manufacturerData) {'companyId': data.companyId, 'payload': base64Encode(data.payload)},
    ],
  };

  /// Returns null for anything unparsable rather than throwing: a single
  /// corrupt entry (an older schema, a truncated write) must not stop the rest
  /// of the remembered list from loading.
  static RememberedDevice? tryFromJson(Map<String, dynamic> json) {
    final deviceId = json['deviceId'];
    if (deviceId is! String || deviceId.isEmpty) return null;

    final kind = RememberedDeviceKind.values.firstWhere(
      (k) => k.name == json['kind'],
      orElse: () => RememberedDeviceKind.controller,
    );

    final manufacturerData = <ManufacturerData>[];
    final rawManufacturerData = json['manufacturerData'];
    if (rawManufacturerData is List) {
      for (final entry in rawManufacturerData) {
        if (entry is! Map) continue;
        final companyId = entry['companyId'];
        final payload = entry['payload'];
        if (companyId is! int || payload is! String) continue;
        manufacturerData.add(ManufacturerData(companyId, Uint8List.fromList(base64Decode(payload))));
      }
    }

    return RememberedDevice(
      deviceId: deviceId,
      name: json['name'] as String?,
      kind: kind,
      lastConnected: DateTime.tryParse(json['lastConnected'] as String? ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0),
      services: [
        for (final service in (json['services'] as List? ?? const []))
          if (service is String) service,
      ],
      manufacturerData: manufacturerData,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is RememberedDevice && other.deviceId == deviceId && other.kind == kind);

  @override
  int get hashCode => Object.hash(deviceId, kind);

  @override
  String toString() => 'RememberedDevice($deviceId, ${name ?? '?'}, ${kind.name})';
}
