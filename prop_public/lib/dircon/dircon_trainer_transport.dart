//INFO: This is a stub - contact me if you need the full implementation.
//
// The full implementation drives a real DirCon (Direct Connect) TCP client.
// This stub keeps the [TrainerTransport] surface so the app compiles.

import 'dart:async';
import 'dart:typed_data';

import 'package:prop/transports/trainer_transport.dart';
import 'package:universal_ble/universal_ble.dart';

/// [TrainerTransport] over a DirCon TCP connection.
class DirconTrainerTransport extends TrainerTransport {
  DirconTrainerTransport({required String id, required this.host, required this.port}) : _id = id;

  final String _id;
  final String host;
  final int port;

  @override
  String get id => _id;

  @override
  Future<void> connect() => throw UnimplementedError();

  @override
  Future<List<BleService>> discoverServices() => throw UnimplementedError();

  @override
  Future<Uint8List> read(String service, String characteristic) => throw UnimplementedError();

  @override
  Future<void> write(String service, String characteristic, Uint8List bytes, {bool withoutResponse = false}) =>
      throw UnimplementedError();

  @override
  Future<void> subscribe(String service, String characteristic, {required bool indicate}) =>
      throw UnimplementedError();

  @override
  Stream<({String characteristic, Uint8List value})> get notifications => const Stream.empty();

  @override
  Future<void> disconnect() async {}
}
