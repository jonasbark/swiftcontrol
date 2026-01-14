import 'dart:async';

import 'package:accessibility/accessibility.dart';
import 'package:bike_control/bluetooth/devices/hid/hid_device.dart';
import 'package:bike_control/utils/actions/base_actions.dart';
import 'package:bike_control/utils/core.dart';
import 'package:bike_control/utils/iap/iap_manager.dart';
import 'package:bike_control/utils/keymap/buttons.dart';
import 'package:dartx/dartx.dart';
import 'package:flutter/services.dart';

import '../keymap/apps/supported_app.dart';
import '../single_line_exception.dart';

class AndroidActions extends BaseActions {
  WindowEvent? windowInfo;

  final accessibilityHandler = Accessibility();
  StreamSubscription<void>? _keymapUpdateSubscription;

  AndroidActions({super.supportedModes = const [SupportedMode.keyboard, SupportedMode.touch, SupportedMode.media]});

  @override
  void init(SupportedApp? supportedApp) {
    super.init(supportedApp);
    streamEvents().listen((windowEvent) {
      if (supportedApp != null) {
        windowInfo = windowEvent;
      }
    });

    // Update handled keys list when keymap changes
    updateHandledKeys();

    // Listen to keymap changes and update handled keys
    _keymapUpdateSubscription?.cancel();
    _keymapUpdateSubscription = supportedApp?.keymap.updateStream.listen((_) {
      updateHandledKeys();
    });

    hidKeyPressed().listen((keyPressed) async {
      final hidDevice = HidDevice(keyPressed.source);
      final button = hidDevice.getOrAddButton(keyPressed.hidKey, () => ControllerButton(keyPressed.hidKey));

      var availableDevice = core.connection.controllerDevices.firstOrNullWhere(
        (e) => e.toString() == hidDevice.toString(),
      );
      if (availableDevice == null) {
        core.connection.addDevices([hidDevice]);
        availableDevice = hidDevice;
      }
      if (keyPressed.keyDown) {
        availableDevice.handleButtonsClicked([button]);
      } else if (keyPressed.keyUp) {
        availableDevice.handleButtonsClicked([]);
      }
    });
  }

  @override
  Future<ActionResult> performAction(ControllerButton button, {required bool isKeyDown, required bool isKeyUp}) async {
    final superResult = await super.performAction(button, isKeyDown: isKeyDown, isKeyUp: isKeyUp);
    if (superResult is! NotHandled) {
      // Increment command count after successful execution
      return superResult;
    }
    final keyPair = supportedApp!.keymap.getKeyPair(button)!;

    if (keyPair.isSpecialKey) {
      await accessibilityHandler.controlMedia(switch (keyPair.physicalKey) {
        PhysicalKeyboardKey.mediaTrackNext => MediaAction.next,
        PhysicalKeyboardKey.mediaPlayPause => MediaAction.playPause,
        PhysicalKeyboardKey.audioVolumeUp => MediaAction.volumeUp,
        PhysicalKeyboardKey.audioVolumeDown => MediaAction.volumeDown,
        _ => throw SingleLineException("No action for key: ${keyPair.physicalKey}"),
      });
      // Increment command count after successful execution
      await IAPManager.instance.incrementCommandCount();
      return Success("Key pressed: ${keyPair.toString()}");
    }

    // Handle keyboard simulation
    if (keyPair.physicalKey != null) {
      final keyCode = _mapPhysicalKeyToAndroidKeyCode(keyPair.physicalKey!);
      if (keyCode != null) {
        try {
          await accessibilityHandler.simulateKeyPress(keyCode, isKeyDown: isKeyDown, isKeyUp: isKeyUp);
          // Increment command count after successful execution
          await IAPManager.instance.incrementCommandCount();
          return Success("Keyboard key pressed: ${keyPair.toString()}");
        } on PlatformException catch (e) {
          return Error("Failed to simulate keyboard: $e");
        }
      }
    }

    final point = await resolveTouchPosition(keyPair: keyPair, windowInfo: windowInfo);
    if (point != Offset.zero) {
      try {
        await accessibilityHandler.performTouch(point.dx, point.dy, isKeyDown: isKeyDown, isKeyUp: isKeyUp);
      } on PlatformException catch (e) {
        return Error("Accessibility Service not working. Follow instructions at https://dontkillmyapp.com/");
      }
      // Increment command count after successful execution
      await IAPManager.instance.incrementCommandCount();
      return Success(
        "Touch performed at: ${point.dx.toInt()}, ${point.dy.toInt()} -> ${isKeyDown && isKeyUp
            ? "click"
            : isKeyDown
            ? "down"
            : "up"}",
      );
    }
    return NotHandled('No action assigned for ${button.name}');
  }

  void ignoreHidDevices() {
    accessibilityHandler.ignoreHidDevices();
  }

  void updateHandledKeys() {
    if (supportedApp == null) {
      accessibilityHandler.setHandledKeys([]);
      return;
    }

    // Get all keys from the keymap that have a mapping defined
    final handledKeys = supportedApp!.keymap.keyPairs
        .filter((keyPair) => !keyPair.hasNoAction)
        .expand((keyPair) => keyPair.buttons)
        .filter((e) => e.action == null && e.icon == null)
        .map((button) => button.name)
        .toSet()
        .toList();

    accessibilityHandler.setHandledKeys(handledKeys);
  }

  /// Maps Flutter PhysicalKeyboardKey to Android KeyEvent key codes
  int? _mapPhysicalKeyToAndroidKeyCode(PhysicalKeyboardKey key) {
    // Android KeyEvent key codes from:
    // https://developer.android.com/reference/android/view/KeyEvent
    
    // Number keys
    if (key == PhysicalKeyboardKey.digit0) return 7; // KEYCODE_0
    if (key == PhysicalKeyboardKey.digit1) return 8; // KEYCODE_1
    if (key == PhysicalKeyboardKey.digit2) return 9; // KEYCODE_2
    if (key == PhysicalKeyboardKey.digit3) return 10; // KEYCODE_3
    if (key == PhysicalKeyboardKey.digit4) return 11; // KEYCODE_4
    if (key == PhysicalKeyboardKey.digit5) return 12; // KEYCODE_5
    if (key == PhysicalKeyboardKey.digit6) return 13; // KEYCODE_6
    if (key == PhysicalKeyboardKey.digit7) return 14; // KEYCODE_7
    if (key == PhysicalKeyboardKey.digit8) return 15; // KEYCODE_8
    if (key == PhysicalKeyboardKey.digit9) return 16; // KEYCODE_9
    
    // Letter keys
    if (key == PhysicalKeyboardKey.keyA) return 29; // KEYCODE_A
    if (key == PhysicalKeyboardKey.keyB) return 30; // KEYCODE_B
    if (key == PhysicalKeyboardKey.keyC) return 31; // KEYCODE_C
    if (key == PhysicalKeyboardKey.keyD) return 32; // KEYCODE_D
    if (key == PhysicalKeyboardKey.keyE) return 33; // KEYCODE_E
    if (key == PhysicalKeyboardKey.keyF) return 34; // KEYCODE_F
    if (key == PhysicalKeyboardKey.keyG) return 35; // KEYCODE_G
    if (key == PhysicalKeyboardKey.keyH) return 36; // KEYCODE_H
    if (key == PhysicalKeyboardKey.keyI) return 37; // KEYCODE_I
    if (key == PhysicalKeyboardKey.keyJ) return 38; // KEYCODE_J
    if (key == PhysicalKeyboardKey.keyK) return 39; // KEYCODE_K
    if (key == PhysicalKeyboardKey.keyL) return 40; // KEYCODE_L
    if (key == PhysicalKeyboardKey.keyM) return 41; // KEYCODE_M
    if (key == PhysicalKeyboardKey.keyN) return 42; // KEYCODE_N
    if (key == PhysicalKeyboardKey.keyO) return 43; // KEYCODE_O
    if (key == PhysicalKeyboardKey.keyP) return 44; // KEYCODE_P
    if (key == PhysicalKeyboardKey.keyQ) return 45; // KEYCODE_Q
    if (key == PhysicalKeyboardKey.keyR) return 46; // KEYCODE_R
    if (key == PhysicalKeyboardKey.keyS) return 47; // KEYCODE_S
    if (key == PhysicalKeyboardKey.keyT) return 48; // KEYCODE_T
    if (key == PhysicalKeyboardKey.keyU) return 49; // KEYCODE_U
    if (key == PhysicalKeyboardKey.keyV) return 50; // KEYCODE_V
    if (key == PhysicalKeyboardKey.keyW) return 51; // KEYCODE_W
    if (key == PhysicalKeyboardKey.keyX) return 52; // KEYCODE_X
    if (key == PhysicalKeyboardKey.keyY) return 53; // KEYCODE_Y
    if (key == PhysicalKeyboardKey.keyZ) return 54; // KEYCODE_Z
    
    // Arrow keys
    if (key == PhysicalKeyboardKey.arrowLeft) return 21; // KEYCODE_DPAD_LEFT
    if (key == PhysicalKeyboardKey.arrowRight) return 22; // KEYCODE_DPAD_RIGHT
    if (key == PhysicalKeyboardKey.arrowUp) return 19; // KEYCODE_DPAD_UP
    if (key == PhysicalKeyboardKey.arrowDown) return 20; // KEYCODE_DPAD_DOWN
    
    // Special characters
    if (key == PhysicalKeyboardKey.minus) return 69; // KEYCODE_MINUS
    if (key == PhysicalKeyboardKey.equal) return 70; // KEYCODE_EQUALS
    if (key == PhysicalKeyboardKey.comma) return 55; // KEYCODE_COMMA
    if (key == PhysicalKeyboardKey.period) return 56; // KEYCODE_PERIOD
    if (key == PhysicalKeyboardKey.slash) return 76; // KEYCODE_SLASH
    if (key == PhysicalKeyboardKey.backslash) return 73; // KEYCODE_BACKSLASH
    if (key == PhysicalKeyboardKey.semicolon) return 74; // KEYCODE_SEMICOLON
    if (key == PhysicalKeyboardKey.quote) return 75; // KEYCODE_APOSTROPHE
    if (key == PhysicalKeyboardKey.bracketLeft) return 71; // KEYCODE_LEFT_BRACKET
    if (key == PhysicalKeyboardKey.bracketRight) return 72; // KEYCODE_RIGHT_BRACKET
    if (key == PhysicalKeyboardKey.backquote) return 68; // KEYCODE_GRAVE
    
    // Function keys
    if (key == PhysicalKeyboardKey.space) return 62; // KEYCODE_SPACE
    if (key == PhysicalKeyboardKey.enter) return 66; // KEYCODE_ENTER
    if (key == PhysicalKeyboardKey.backspace) return 67; // KEYCODE_DEL
    if (key == PhysicalKeyboardKey.tab) return 61; // KEYCODE_TAB
    if (key == PhysicalKeyboardKey.escape) return 111; // KEYCODE_ESCAPE
    
    // Additional keys
    if (key == PhysicalKeyboardKey.delete) return 112; // KEYCODE_FORWARD_DEL
    if (key == PhysicalKeyboardKey.pageUp) return 92; // KEYCODE_PAGE_UP
    if (key == PhysicalKeyboardKey.pageDown) return 93; // KEYCODE_PAGE_DOWN
    if (key == PhysicalKeyboardKey.home) return 122; // KEYCODE_MOVE_HOME
    if (key == PhysicalKeyboardKey.end) return 123; // KEYCODE_MOVE_END
    
    // Numpad keys
    if (key == PhysicalKeyboardKey.numpad0) return 144; // KEYCODE_NUMPAD_0
    if (key == PhysicalKeyboardKey.numpad1) return 145; // KEYCODE_NUMPAD_1
    if (key == PhysicalKeyboardKey.numpad2) return 146; // KEYCODE_NUMPAD_2
    if (key == PhysicalKeyboardKey.numpad3) return 147; // KEYCODE_NUMPAD_3
    if (key == PhysicalKeyboardKey.numpad4) return 148; // KEYCODE_NUMPAD_4
    if (key == PhysicalKeyboardKey.numpad5) return 149; // KEYCODE_NUMPAD_5
    if (key == PhysicalKeyboardKey.numpad6) return 150; // KEYCODE_NUMPAD_6
    if (key == PhysicalKeyboardKey.numpad7) return 151; // KEYCODE_NUMPAD_7
    if (key == PhysicalKeyboardKey.numpad8) return 152; // KEYCODE_NUMPAD_8
    if (key == PhysicalKeyboardKey.numpad9) return 153; // KEYCODE_NUMPAD_9
    if (key == PhysicalKeyboardKey.numpadAdd) return 157; // KEYCODE_NUMPAD_ADD
    if (key == PhysicalKeyboardKey.numpadSubtract) return 156; // KEYCODE_NUMPAD_SUBTRACT
    if (key == PhysicalKeyboardKey.numpadMultiply) return 155; // KEYCODE_NUMPAD_MULTIPLY
    if (key == PhysicalKeyboardKey.numpadDivide) return 154; // KEYCODE_NUMPAD_DIVIDE
    if (key == PhysicalKeyboardKey.numpadEnter) return 160; // KEYCODE_NUMPAD_ENTER
    
    return null;
  }
}
