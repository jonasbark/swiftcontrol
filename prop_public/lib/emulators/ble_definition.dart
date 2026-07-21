import 'dart:typed_data';

import 'package:prop/emulators/transporter/transporter.dart';
import 'package:prop/utils/constants.dart';
import 'package:universal_ble/universal_ble.dart';

/// Describes a virtual BLE peripheral: the services/characteristics it
/// exposes, and what happens when the connected client reads, writes, or
/// subscribes.
abstract class BleDefinition {
  Transporter? _transporter;

  /// Set by the [Transporter] when a definition is bound to it.
  Transporter? get transporter => _transporter;
  set transporter(Transporter? value) {
    _transporter = value;
  }

  List<String> get serviceUUIDs;

  List<String> get advertiseServiceUUIDs;

  /// Optional custom advertisement (local name + manufacturer data).
  PeripheralAdvertisement? get advertisement => null;

  List<BleCharacteristic> getCharacteristics(String serviceUUID);

  void onWriteRequest(String characteristicUUID, List<int> characteristicData);

  Future<Uint8List>? onReadRequest(String characteristicUUID) => null;

  void onNotification(String characteristic, Uint8List bytes);

  void onEnableNotificationRequest(String characteristicUUID) {}

  void sendCharacteristicNotification(
    String characteristicUUID,
    List<int> data, {
    int responseCode = FtmsMdnsConstants.DC_RC_REQUEST_COMPLETED_SUCCESSFULLY,
  }) {
    transporter?.sendCharacteristicNotification(characteristicUUID, data, responseCode: responseCode);
  }

  void dispose() {}

  void debug() {}
}

/// Transport-agnostic description of a BLE advertisement.
class PeripheralAdvertisement {
  final String? name;
  final List<String> serviceUUIDs;
  final ManufacturerData? manufacturerData;

  const PeripheralAdvertisement({
    this.name,
    this.serviceUUIDs = const [],
    this.manufacturerData,
  });
}
