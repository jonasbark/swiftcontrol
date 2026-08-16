import 'dart:io' show Platform;

import 'package:bike_control/services/overlay/android_overlay_controller.dart';
import 'package:bike_control/services/overlay/desktop_overlay_controller.dart';
import 'package:bike_control/services/overlay/ios_overlay_controller.dart';
import 'package:bike_control/services/overlay/trainer_overlay_controller.dart';
import 'package:flutter/foundation.dart';

class TrainerOverlayService {
  TrainerOverlayService._();
  static TrainerOverlayController? _instance;

  static TrainerOverlayController forCurrentPlatform() {
    return _instance ??= _build();
  }

  /// Whether this platform can draw an overlay at all — i.e. whether
  /// [forCurrentPlatform] would hand back something other than a no-op.
  /// Answered without building a controller, so callers on a hot path (the
  /// home screen rebuilds on every BLE event) don't spin up platform channels
  /// just to ask.
  static bool get isSupportedPlatform {
    if (kIsWeb) return false;
    return Platform.isAndroid || Platform.isIOS || Platform.isMacOS || Platform.isWindows;
  }

  static TrainerOverlayController _build() {
    if (kIsWeb) return NoOpOverlayController();
    if (Platform.isAndroid) return AndroidOverlayController();
    if (Platform.isIOS) return IosOverlayController();
    if (Platform.isMacOS || Platform.isWindows) return DesktopOverlayController();
    return NoOpOverlayController();
  }

  @visibleForTesting
  static void resetForTest() {
    _instance = null;
  }
}
