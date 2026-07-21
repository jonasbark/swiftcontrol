//INFO: This is a stub - contact me if you need the full implementation.

import 'dart:io';

import 'package:prop/emulators/transporter/transporter.dart';

class NetworkTransporter extends Transporter {
  Socket? socket;
  NetworkTransporter({this.socket, required super.definition});

  @override
  void sendCharacteristicNotification(String characteristicUUID, List<int> data, {int responseCode = 1}) {}

  void handleIncomingData(List<int> data) {}
}
