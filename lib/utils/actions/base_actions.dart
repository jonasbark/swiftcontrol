import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:swift_control/utils/actions/android.dart';
import 'package:swift_control/utils/actions/desktop.dart';
import 'package:swift_control/utils/keymap/buttons.dart';

import '../keymap/apps/supported_app.dart';

enum SupportedMode { keyboard, touch, media }

abstract class BaseActions {
  final List<SupportedMode> supportedModes;

  SupportedApp? supportedApp;

  BaseActions({required this.supportedModes});

  void init(SupportedApp? supportedApp) {
    this.supportedApp = supportedApp;
  }

  Future<Offset> resolveTouchPosition({required ControllerButton action}) async {
    final keyPair = supportedApp!.keymap.getKeyPair(action);
    if (keyPair != null && keyPair.touchPosition != Offset.zero) {
      // convert relative position to absolute position based on window info

      // TODO support multiple screens
      final Size displaySize;
      final double devicePixelRatio;
      if (Platform.isWindows) {
        // TODO remove once https://github.com/flutter/flutter/pull/164460 is available in stable
        final display = await screenRetriever.getPrimaryDisplay();
        displaySize = display.size;
        devicePixelRatio = 1.0;
      } else {
        final display = WidgetsBinding.instance.platformDispatcher.views.first.display;
        displaySize = display.size;
        devicePixelRatio = display.devicePixelRatio;
      }

      late final Size physicalSize;
      if (this is AndroidActions) {
        // display size is already in physical pixels
        physicalSize = displaySize;
      } else if (this is DesktopActions) {
        // display size is in logical pixels, convert to physical pixels
        // TODO on macOS the notch is included here, but it's not part of the usable screen area, so we should exclude it
        physicalSize = displaySize / devicePixelRatio;
      } else {
        physicalSize = displaySize;
      }

      final x = (keyPair.touchPosition.dx / 100.0) * physicalSize.width;
      final y = (keyPair.touchPosition.dy / 100.0) * physicalSize.height;

      if (kDebugMode) {
        print("Screen size: $physicalSize => Touch at: $x, $y");
      }
      return Offset(x, y);
    }
    return Offset.zero;
  }

  Future<String> performAction(ControllerButton action, {bool isKeyDown = true, bool isKeyUp = false});
}

class StubActions extends BaseActions {
  StubActions({super.supportedModes = const []});

  @override
  Future<String> performAction(ControllerButton action, {bool isKeyDown = true, bool isKeyUp = false}) {
    return Future.value(action.name);
  }
}
