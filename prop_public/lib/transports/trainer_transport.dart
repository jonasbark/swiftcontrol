import 'dart:async';
import 'dart:typed_data';

import 'package:universal_ble/universal_ble.dart';

/// Upstream transport to a real trainer. Implementations: BLE
/// ([BleTrainerTransport], wrapping UniversalBle) and DirCon over TCP
/// ([DirconTrainerTransport]). Definitions perform all upstream I/O through
/// this interface so they stay transport-blind.
abstract class TrainerTransport {
  /// Upstream identity — the BLE deviceId or the synthetic mDNS id.
  String get id;

  /// Invoked when the transport drops unexpectedly.
  void Function()? onDisconnected;

  Future<void> connect();
  Future<List<BleService>> discoverServices();
  Future<Uint8List> read(String service, String characteristic);
  Future<void> write(String service, String characteristic, Uint8List bytes, {bool withoutResponse = false});
  Future<void> subscribe(String service, String characteristic, {required bool indicate});

  /// Characteristic notifications from the upstream trainer.
  Stream<({String characteristic, Uint8List value})> get notifications;

  Future<void> disconnect();
}
