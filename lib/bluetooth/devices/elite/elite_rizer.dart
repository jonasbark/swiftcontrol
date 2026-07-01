import 'package:bike_control/bluetooth/devices/bluetooth_device.dart';
import 'package:bike_control/bluetooth/devices/elite/elite_rizer_protocol.dart';
import 'package:bike_control/bluetooth/incline/manual_incline_device.dart';
import 'package:bike_control/main.dart';
import 'package:dartx/dartx.dart';
import 'package:flutter/foundation.dart';
import 'package:universal_ble/universal_ble.dart';

/// Elite Rizer — a beta device that simulates incline (driven by the bridge's
/// grade, via [ManualInclineDevice]). It is a standalone BLE device, so it works
/// with any trainer. (Steering is added in a later task.)
class EliteRizer extends BluetoothDevice with ManualInclineDevice {
  EliteRizer(super.scanResult) : super(availableButtons: const [], isBeta: true);

  @visibleForTesting
  Future<void> Function(Uint8List bytes)? debugWriteSink;

  @override
  Future<void> handleServices(List<BleService> services) async {
    for (final s in services) {
      debugPrint('[Rizer] service ${s.uuid} chars=${s.characteristics.map((c) => c.uuid).toList()}');
    }
    final service = services.firstOrNullWhere((e) => e.uuid == eliteRizerServiceUuid);
    if (service == null) {
      debugPrint('[Rizer] service $eliteRizerServiceUuid not found — incompatible device');
      return;
    }
    final write = service.characteristics.firstOrNullWhere((e) => e.uuid == eliteRizerWriteCharacteristicUuid);
    if (write == null) {
      debugPrint('[Rizer] write char $eliteRizerWriteCharacteristicUuid not found — incompatible device');
      return;
    }
    // Enable notifications on status + current-incline (steering added later).
    for (final uuid in [eliteRizerStatusCharacteristicUuid, eliteRizerInclineCharacteristicUuid]) {
      final ch = service.characteristics.firstOrNullWhere((e) => e.uuid == uuid);
      if (ch != null) {
        try {
          await UniversalBle.subscribeNotifications(device.deviceId, service.uuid, ch.uuid);
        } catch (e, s) {
          recordError(e, s, context: 'EliteRizer: subscribe $uuid failed');
        }
      }
    }
  }

  @override
  Future<void> processCharacteristic(String characteristic, Uint8List bytes) async {
    if (characteristic == eliteRizerStatusCharacteristicUuid) {
      debugPrint('[Rizer] status: $bytes'); // byte[2]==2 => success
    } else if (characteristic == eliteRizerInclineCharacteristicUuid) {
      debugPrint('[Rizer] current incline: $bytes');
    } else {
      debugPrint('[Rizer] notify $characteristic: $bytes');
    }
  }

  @override
  Future<bool> writeInclineRaw(int grade001Pct) async {
    try {
      final bytes = rizerInclineToBytes(grade001Pct);
      if (debugWriteSink != null) {
        await debugWriteSink!(bytes);
      } else {
        await UniversalBle.write(
          device.deviceId, eliteRizerServiceUuid, eliteRizerWriteCharacteristicUuid, bytes,
          withoutResponse: false,
        );
      }
      return true;
    } catch (e, s) {
      recordError(e, s, context: 'EliteRizer: writeIncline failed');
      return false;
    }
  }
}
