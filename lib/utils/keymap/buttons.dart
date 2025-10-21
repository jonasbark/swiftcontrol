import 'package:flutter/material.dart';
import 'package:swift_control/widgets/keymap_explanation.dart';

enum InGameAction {
  shiftUp,
  shiftDown,
  navigateLeft,
  navigateRight,
  increaseResistance,
  decreaseResistance,
  toggleUi,
  cameraAngle,
  emote,
  uturn,
  steering;

  @override
  String toString() {
    return name.splitByUpperCase();
  }
}

enum ControllerButton {
  // left controller
  navigationUp._(null, icon: Icons.keyboard_arrow_up, color: Colors.black),
  navigationDown._(InGameAction.uturn, icon: Icons.keyboard_arrow_down, color: Colors.black),
  navigationLeft._(InGameAction.navigateLeft, icon: Icons.keyboard_arrow_left, color: Colors.black),
  navigationRight._(InGameAction.navigateRight, icon: Icons.keyboard_arrow_right, color: Colors.black),
  onOffLeft._(InGameAction.toggleUi),
  sideButtonLeft._(InGameAction.shiftDown),
  paddleLeft._(InGameAction.shiftDown),

  // zwift ride only
  shiftUpLeft._(InGameAction.shiftDown, icon: Icons.remove, color: Colors.black),
  shiftDownLeft._(InGameAction.shiftDown, icon: Icons.remove, color: Colors.black),
  powerUpLeft._(InGameAction.shiftDown),

  // right controller
  a._(null, color: Colors.lightGreen),
  b._(null, color: Colors.pinkAccent),
  z._(null, color: Colors.deepOrangeAccent),
  y._(null, color: Colors.lightBlue),
  onOffRight._(InGameAction.toggleUi),
  sideButtonRight._(InGameAction.shiftUp),
  paddleRight._(InGameAction.shiftUp),

  // zwift ride only
  shiftUpRight._(InGameAction.shiftUp, icon: Icons.add, color: Colors.black),
  shiftDownRight._(InGameAction.shiftUp),
  powerUpRight._(InGameAction.shiftUp),

  // elite square only
  campagnoloLeft._(InGameAction.shiftDown),
  campagnoloRight._(InGameAction.shiftUp);

  final InGameAction? action;
  final Color? color;
  final IconData? icon;
  const ControllerButton._(this.action, {this.color, this.icon});

  @override
  String toString() {
    return name;
  }
}
