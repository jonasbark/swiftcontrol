//INFO: This is a stub - contact me if you need the full implementation.
//
// The full implementation decodes the Zwift Click/Play pairing pages and
// drives the periodic RESET recovery. This stub keeps the static surface so
// the app compiles.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:universal_ble/universal_ble.dart';

class ClickLogic {
  static final _resettingDevices = <String>{};

  static bool isResetting(String deviceId) => _resettingDevices.contains(deviceId);

  static void clearResetting(String deviceId) => _resettingDevices.remove(deviceId);

  /// Invoked right before a RESET command is sent.
  static void Function(String deviceId)? onResetSent;

  static void processData(Uint8List bytes, {required String deviceId, required List<BleService> services}) {}

  static Future<void> setupHandshake(List<BleService> services, String deviceId, {required bool isRight}) async {}

  static void resetTimer() {}
}
