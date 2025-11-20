import 'package:flutter/material.dart';
import 'package:swift_control/utils/keymap/buttons.dart';

class ZwiftButtons {
  // left controller
  static const ControllerButton navigationUp = ControllerButton(
    'navigationUp',
    action: InGameAction.toggleUi,
    icon: Icons.keyboard_arrow_up,
    color: Colors.black,
  );
  static const ControllerButton navigationDown = ControllerButton(
    'navigationDown',
    action: InGameAction.uturn,
    icon: Icons.keyboard_arrow_down,
    color: Colors.black,
  );
  static const ControllerButton navigationLeft = ControllerButton(
    'navigationLeft',
    action: InGameAction.navigateLeft,
    icon: Icons.keyboard_arrow_left,
    color: Colors.black,
  );
  static const ControllerButton navigationRight = ControllerButton(
    'navigationRight',
    action: InGameAction.navigateRight,
    icon: Icons.keyboard_arrow_right,
    color: Colors.black,
  );
  static const ControllerButton onOffLeft = ControllerButton('onOffLeft', action: InGameAction.toggleUi);
  static const ControllerButton sideButtonLeft = ControllerButton('sideButtonLeft', action: InGameAction.shiftDown);
  static const ControllerButton paddleLeft = ControllerButton('paddleLeft', action: InGameAction.shiftDown);

  // zwift ride only
  static const ControllerButton shiftUpLeft = ControllerButton(
    'shiftUpLeft',
    action: InGameAction.shiftDown,
    icon: Icons.remove,
    color: Colors.black,
  );
  static const ControllerButton shiftDownLeft = ControllerButton(
    'shiftDownLeft',
    action: InGameAction.shiftDown,
  );
  static const ControllerButton powerUpLeft = ControllerButton('powerUpLeft', action: InGameAction.shiftDown);

  // right controller
  static const ControllerButton a = ControllerButton('a', action: null, color: Colors.lightGreen);
  static const ControllerButton b = ControllerButton('b', action: null, color: Colors.pinkAccent);
  static const ControllerButton z = ControllerButton('z', action: null, color: Colors.deepOrangeAccent);
  static const ControllerButton y = ControllerButton('y', action: null, color: Colors.lightBlue);
  static const ControllerButton onOffRight = ControllerButton('onOffRight', action: InGameAction.toggleUi);
  static const ControllerButton sideButtonRight = ControllerButton('sideButtonRight', action: InGameAction.shiftUp);
  static const ControllerButton paddleRight = ControllerButton('paddleRight', action: InGameAction.shiftUp);

  // zwift ride only
  static const ControllerButton shiftUpRight = ControllerButton(
    'shiftUpRight',
    action: InGameAction.shiftUp,
    icon: Icons.add,
    color: Colors.black,
  );
  static const ControllerButton shiftDownRight = ControllerButton('shiftDownRight', action: InGameAction.shiftUp);
  static const ControllerButton powerUpRight = ControllerButton('powerUpRight', action: InGameAction.shiftUp);

  static List<ControllerButton> get values => [
    // left
    navigationUp,
    navigationDown,
    navigationLeft,
    navigationRight,
    onOffLeft,
    sideButtonLeft,
    paddleLeft,
    shiftUpLeft,
    shiftDownLeft,
    powerUpLeft,
    // right
    a,
    b,
    z,
    y,
    onOffRight,
    sideButtonRight,
    paddleRight,
    shiftUpRight,
    shiftDownRight,
    powerUpRight,
  ];
}
