import 'dart:async';
import 'dart:typed_data';

import 'package:dartx/dartx.dart';
import 'package:prop/prop.dart';
import 'package:universal_ble/universal_ble.dart';

/// `universal_ble`-backed [SramTransport]. Notifications flow through the app's
/// existing pipeline; the owning device calls [onNotification] from its
/// `processCharacteristic` callback.
class SramBleTransport implements SramTransport {
  SramBleTransport(this.deviceId, this.services);

  final String deviceId;
  final List<BleService> services;

  final Map<String, StreamController<Uint8List>> _controllers = {};

  StreamController<Uint8List> _ctrl(String characteristic) => _controllers.putIfAbsent(
        characteristic.toLowerCase(),
        () => StreamController<Uint8List>.broadcast(),
      );

  void onNotification(String characteristic, Uint8List value) =>
      _ctrl(characteristic).add(value);

  String? _serviceFor(String characteristic) => services
      .firstOrNullWhere((s) => s.characteristics.any((c) => c.uuid == characteristic.toLowerCase()))
      ?.uuid;

  @override
  Future<void> subscribe(String characteristic) async {
    final service = _serviceFor(characteristic);
    if (service == null) return;
    await UniversalBle.subscribeNotifications(deviceId, service, characteristic.toLowerCase());
  }

  @override
  Future<void> write(String characteristic, Uint8List data, {bool withoutResponse = false}) async {
    final service = _serviceFor(characteristic);
    if (service == null) throw StateError('SRAM: no service for $characteristic');
    await UniversalBle.write(deviceId, service, characteristic.toLowerCase(), data,
        withoutResponse: withoutResponse);
  }

  @override
  Future<Uint8List> read(String characteristic) async {
    final service = _serviceFor(characteristic);
    if (service == null) throw StateError('SRAM: no service for $characteristic');
    return UniversalBle.read(deviceId, service, characteristic.toLowerCase());
  }

  @override
  Stream<Uint8List> notifications(String characteristic) => _ctrl(characteristic).stream;

  @override
  List<String> readWriteCharacteristics() => [
        for (final service in services)
          for (final c in service.characteristics)
            if (c.properties.contains(CharacteristicProperty.read) &&
                c.properties.contains(CharacteristicProperty.write))
              c.uuid,
      ];
}
