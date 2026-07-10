/// Factory for the platform implementation universal_ble would have selected
/// itself. Needed because UniversalBle.setInstance() replaces the platform
/// wholesale and offers no getter for the default.
library;

export 'real_ble_platform_stub.dart'
    if (dart.library.io) 'real_ble_platform_io.dart'
    if (dart.library.js_interop) 'real_ble_platform_web.dart';
