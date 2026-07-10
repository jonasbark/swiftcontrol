import 'package:universal_ble/universal_ble.dart';

UniversalBlePlatform createRealBlePlatform() =>
    throw UnsupportedError('No BLE platform available on this target');
