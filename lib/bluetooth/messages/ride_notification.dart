import 'dart:typed_data';

import 'package:dartx/dartx.dart';
import 'package:swift_control/bluetooth/messages/notification.dart';
import 'package:swift_control/bluetooth/protocol/zwift.pb.dart';
import 'package:swift_control/utils/keymap/buttons.dart';

enum _RideButtonMask {
  LEFT_BTN(0x00001),
  UP_BTN(0x00002),
  RIGHT_BTN(0x00004),
  DOWN_BTN(0x00008),

  A_BTN(0x00010),
  B_BTN(0x00020),
  Y_BTN(0x00040),
  TILT_LEFT_BTN(0x00080),  // ZL button - was missing

  Z_BTN(0x00100),
  SHFT_UP_L_BTN(0x00200),
  SHFT_DN_L_BTN(0x00400),
  POWERUP_L_BTN(0x00800),
  ONOFF_L_BTN(0x01000),
  SHFT_UP_R_BTN(0x02000),
  SHFT_DN_R_BTN(0x04000),
  TILT_RIGHT_BTN(0x08000), // ZR button - was missing

  POWERUP_R_BTN(0x10000),
  ONOFF_R_BTN(0x20000);

  final int mask;

  const _RideButtonMask(this.mask);
}

class RideNotification extends BaseNotification {
  late List<ZwiftButton> buttonsClicked;

  RideNotification(Uint8List message) {
    final status = RideKeyPadStatus.fromBuffer(message);

    buttonsClicked = [
      if (status.buttonMap & _RideButtonMask.LEFT_BTN.mask != 0) ZwiftButton.navigationLeft,
      if (status.buttonMap & _RideButtonMask.RIGHT_BTN.mask != 0) ZwiftButton.navigationRight,
      if (status.buttonMap & _RideButtonMask.UP_BTN.mask != 0) ZwiftButton.navigationUp,
      if (status.buttonMap & _RideButtonMask.DOWN_BTN.mask != 0) ZwiftButton.navigationDown,
      if (status.buttonMap & _RideButtonMask.A_BTN.mask != 0) ZwiftButton.a,
      if (status.buttonMap & _RideButtonMask.B_BTN.mask != 0) ZwiftButton.b,
      if (status.buttonMap & _RideButtonMask.Y_BTN.mask != 0) ZwiftButton.y,
      if (status.buttonMap & _RideButtonMask.Z_BTN.mask != 0) ZwiftButton.z,
      if (status.buttonMap & _RideButtonMask.TILT_LEFT_BTN.mask != 0) ZwiftButton.tiltLeft,
      if (status.buttonMap & _RideButtonMask.TILT_RIGHT_BTN.mask != 0) ZwiftButton.tiltRight,
      if (status.buttonMap & _RideButtonMask.SHFT_UP_L_BTN.mask != 0) ZwiftButton.shiftUpLeft,
      if (status.buttonMap & _RideButtonMask.SHFT_DN_L_BTN.mask != 0) ZwiftButton.shiftDownLeft,
      if (status.buttonMap & _RideButtonMask.SHFT_UP_R_BTN.mask != 0) ZwiftButton.shiftUpRight,
      if (status.buttonMap & _RideButtonMask.SHFT_DN_R_BTN.mask != 0) ZwiftButton.shiftDownRight,
      if (status.buttonMap & _RideButtonMask.POWERUP_L_BTN.mask != 0) ZwiftButton.powerUpLeft,
      if (status.buttonMap & _RideButtonMask.POWERUP_R_BTN.mask != 0) ZwiftButton.powerUpRight,
      if (status.buttonMap & _RideButtonMask.ONOFF_L_BTN.mask != 0) ZwiftButton.onOffLeft,
      if (status.buttonMap & _RideButtonMask.ONOFF_R_BTN.mask != 0) ZwiftButton.onOffRight,
    ];

    for (final analogue in status.analogButtons.groupStatus) {
      if (analogue.analogValue.abs() == 100) {
        if (analogue.location == RideAnalogLocation.LEFT) {
          buttonsClicked.add(ZwiftButton.paddleLeft);
        } else if (analogue.location == RideAnalogLocation.RIGHT) {
          buttonsClicked.add(ZwiftButton.paddleRight);
        } else if (analogue.location == RideAnalogLocation.DOWN || analogue.location == RideAnalogLocation.UP) {
          // TODO what is this even?
        }
      }
    }
  }

  @override
  String toString() {
    return 'Buttons: ${buttonsClicked.joinToString(transform: (e) => e.name)}';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RideNotification &&
          runtimeType == other.runtimeType &&
          buttonsClicked.contentEquals(other.buttonsClicked);

  @override
  int get hashCode => buttonsClicked.hashCode;
}
