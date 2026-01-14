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

  /// Android KeyEvent key codes mapping
  /// Reference: https://developer.android.com/reference/android/view/KeyEvent
  static final Map<PhysicalKeyboardKey, int> _keyCodeMap = {
    // Number keys
    PhysicalKeyboardKey.digit0: 7, // KEYCODE_0
    PhysicalKeyboardKey.digit1: 8, // KEYCODE_1
    PhysicalKeyboardKey.digit2: 9, // KEYCODE_2
    PhysicalKeyboardKey.digit3: 10, // KEYCODE_3
    PhysicalKeyboardKey.digit4: 11, // KEYCODE_4
    PhysicalKeyboardKey.digit5: 12, // KEYCODE_5
    PhysicalKeyboardKey.digit6: 13, // KEYCODE_6
    PhysicalKeyboardKey.digit7: 14, // KEYCODE_7
    PhysicalKeyboardKey.digit8: 15, // KEYCODE_8
    PhysicalKeyboardKey.digit9: 16, // KEYCODE_9
    
    // Letter keys
    PhysicalKeyboardKey.keyA: 29, // KEYCODE_A
    PhysicalKeyboardKey.keyB: 30, // KEYCODE_B
    PhysicalKeyboardKey.keyC: 31, // KEYCODE_C
    PhysicalKeyboardKey.keyD: 32, // KEYCODE_D
    PhysicalKeyboardKey.keyE: 33, // KEYCODE_E
    PhysicalKeyboardKey.keyF: 34, // KEYCODE_F
    PhysicalKeyboardKey.keyG: 35, // KEYCODE_G
    PhysicalKeyboardKey.keyH: 36, // KEYCODE_H
    PhysicalKeyboardKey.keyI: 37, // KEYCODE_I
    PhysicalKeyboardKey.keyJ: 38, // KEYCODE_J
    PhysicalKeyboardKey.keyK: 39, // KEYCODE_K
    PhysicalKeyboardKey.keyL: 40, // KEYCODE_L
    PhysicalKeyboardKey.keyM: 41, // KEYCODE_M
    PhysicalKeyboardKey.keyN: 42, // KEYCODE_N
    PhysicalKeyboardKey.keyO: 43, // KEYCODE_O
    PhysicalKeyboardKey.keyP: 44, // KEYCODE_P
    PhysicalKeyboardKey.keyQ: 45, // KEYCODE_Q
    PhysicalKeyboardKey.keyR: 46, // KEYCODE_R
    PhysicalKeyboardKey.keyS: 47, // KEYCODE_S
    PhysicalKeyboardKey.keyT: 48, // KEYCODE_T
    PhysicalKeyboardKey.keyU: 49, // KEYCODE_U
    PhysicalKeyboardKey.keyV: 50, // KEYCODE_V
    PhysicalKeyboardKey.keyW: 51, // KEYCODE_W
    PhysicalKeyboardKey.keyX: 52, // KEYCODE_X
    PhysicalKeyboardKey.keyY: 53, // KEYCODE_Y
    PhysicalKeyboardKey.keyZ: 54, // KEYCODE_Z
    
    // Arrow keys
    PhysicalKeyboardKey.arrowLeft: 21, // KEYCODE_DPAD_LEFT
    PhysicalKeyboardKey.arrowRight: 22, // KEYCODE_DPAD_RIGHT
    PhysicalKeyboardKey.arrowUp: 19, // KEYCODE_DPAD_UP
    PhysicalKeyboardKey.arrowDown: 20, // KEYCODE_DPAD_DOWN
    
    // Special characters
    PhysicalKeyboardKey.minus: 69, // KEYCODE_MINUS
    PhysicalKeyboardKey.equal: 70, // KEYCODE_EQUALS
    PhysicalKeyboardKey.comma: 55, // KEYCODE_COMMA
    PhysicalKeyboardKey.period: 56, // KEYCODE_PERIOD
    PhysicalKeyboardKey.slash: 76, // KEYCODE_SLASH
    PhysicalKeyboardKey.backslash: 73, // KEYCODE_BACKSLASH
    PhysicalKeyboardKey.semicolon: 74, // KEYCODE_SEMICOLON
    PhysicalKeyboardKey.quote: 75, // KEYCODE_APOSTROPHE
    PhysicalKeyboardKey.bracketLeft: 71, // KEYCODE_LEFT_BRACKET
    PhysicalKeyboardKey.bracketRight: 72, // KEYCODE_RIGHT_BRACKET
    PhysicalKeyboardKey.backquote: 68, // KEYCODE_GRAVE
    
    // Function keys
    PhysicalKeyboardKey.space: 62, // KEYCODE_SPACE
    PhysicalKeyboardKey.enter: 66, // KEYCODE_ENTER
    PhysicalKeyboardKey.backspace: 67, // KEYCODE_DEL
    PhysicalKeyboardKey.tab: 61, // KEYCODE_TAB
    PhysicalKeyboardKey.escape: 111, // KEYCODE_ESCAPE
    
    // Additional keys
    PhysicalKeyboardKey.delete: 112, // KEYCODE_FORWARD_DEL
    PhysicalKeyboardKey.pageUp: 92, // KEYCODE_PAGE_UP
    PhysicalKeyboardKey.pageDown: 93, // KEYCODE_PAGE_DOWN
    PhysicalKeyboardKey.home: 122, // KEYCODE_MOVE_HOME
    PhysicalKeyboardKey.end: 123, // KEYCODE_MOVE_END
    
    // Numpad keys
    PhysicalKeyboardKey.numpad0: 144, // KEYCODE_NUMPAD_0
    PhysicalKeyboardKey.numpad1: 145, // KEYCODE_NUMPAD_1
    PhysicalKeyboardKey.numpad2: 146, // KEYCODE_NUMPAD_2
    PhysicalKeyboardKey.numpad3: 147, // KEYCODE_NUMPAD_3
    PhysicalKeyboardKey.numpad4: 148, // KEYCODE_NUMPAD_4
    PhysicalKeyboardKey.numpad5: 149, // KEYCODE_NUMPAD_5
    PhysicalKeyboardKey.numpad6: 150, // KEYCODE_NUMPAD_6
    PhysicalKeyboardKey.numpad7: 151, // KEYCODE_NUMPAD_7
    PhysicalKeyboardKey.numpad8: 152, // KEYCODE_NUMPAD_8
    PhysicalKeyboardKey.numpad9: 153, // KEYCODE_NUMPAD_9
    PhysicalKeyboardKey.numpadAdd: 157, // KEYCODE_NUMPAD_ADD
    PhysicalKeyboardKey.numpadSubtract: 156, // KEYCODE_NUMPAD_SUBTRACT
    PhysicalKeyboardKey.numpadMultiply: 155, // KEYCODE_NUMPAD_MULTIPLY
    PhysicalKeyboardKey.numpadDivide: 154, // KEYCODE_NUMPAD_DIVIDE
    PhysicalKeyboardKey.numpadEnter: 160, // KEYCODE_NUMPAD_ENTER
  };

  /// Maps Flutter PhysicalKeyboardKey to Android KeyEvent key codes
  int? _mapPhysicalKeyToAndroidKeyCode(PhysicalKeyboardKey key) {
    return _keyCodeMap[key];
  }
}
