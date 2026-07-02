// ignore: implementation_imports
import 'package:universal_ble/src/universal_ble_web/universal_ble_web.dart';
import 'package:universal_ble/universal_ble.dart';

UniversalBlePlatform createRealBlePlatform() => UniversalBleWeb.instance;
