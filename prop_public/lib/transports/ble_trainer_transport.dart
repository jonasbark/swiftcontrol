//INFO: This is a stub - contact me if you need the full implementation.
//
// The full implementation forwards through UniversalBle. This stub keeps the
// [TrainerTransport] surface so the app compiles.

import 'dart:async';
import 'dart:typed_data';

import 'package:prop/transports/trainer_transport.dart';
import 'package:universal_ble/universal_ble.dart';

class BleTrainerTransport extends TrainerTransport {
  BleTrainerTransport(this.deviceId);

  final String deviceId;

  @override
  String get id => deviceId;

  @override
  Future<void> connect() async {}

  @override
  Future<List<BleService>> discoverServices() async => const [];

  @override
  Future<Uint8List> read(String service, String characteristic) => throw UnimplementedError();

  @override
  Future<void> write(String service, String characteristic, Uint8List bytes, {bool withoutResponse = false}) async {}

  @override
  Future<void> subscribe(String service, String characteristic, {required bool indicate}) async {}

  @override
  Stream<({String characteristic, Uint8List value})> get notifications => const Stream.empty();

  @override
  Future<void> disconnect() async {}
}
