import 'package:flutter/foundation.dart';
// Mirrors universal_ble's private _defaultPlatform() selection.
// ignore: implementation_imports
import 'package:universal_ble/src/universal_ble_linux/universal_ble_linux_instance_io.dart';
// ignore: implementation_imports
import 'package:universal_ble/src/universal_ble_pigeon/universal_ble_pigeon_channel.dart';
import 'package:universal_ble/universal_ble.dart';

UniversalBlePlatform createRealBlePlatform() {
  if (defaultTargetPlatform == TargetPlatform.linux) return universalBleLinuxInstance;
  return UniversalBlePigeonChannel.instance;
}
