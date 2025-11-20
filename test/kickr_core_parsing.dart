import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:swift_control/bluetooth/devices/wahoo/wahoo_kickr_bike_shift.dart';
import 'package:swift_control/bluetooth/devices/zwift/protocol/zp.pbenum.dart';
import 'package:swift_control/bluetooth/devices/zwift/protocol/zwift.pb.dart' show RideKeyPadStatus;
import 'package:swift_control/bluetooth/devices/zwift/zwift_ride.dart';
import 'package:swift_control/main.dart';
import 'package:swift_control/utils/actions/base_actions.dart';
import 'package:universal_ble/universal_ble.dart';

void main() {
  final kickrBikeShift = WahooKickrBikeShift(BleDevice(deviceId: '', name: ''));
  final stubActions = StubActions();
  actionHandler = stubActions;

  final button = RideButtonMask.DOWN_BTN;
  final status = RideKeyPadStatus()
    ..buttonMap = (~button.mask) & 0xFFFFFFFF
    ..analogPaddles.clear();

  final bytes = status.writeToBuffer();

  final commandProto = Uint8List.fromList([
    Opcode.CONTROLLER_NOTIFICATION.value,
    ...bytes,
  ]);
  print(commandProto);

  group('Kickr Core Button parsing', () {
    test('rightUp pressed', () async {
      final frame = kickrBikeShift.parseShortFrame('0001E6')!;
      expect(frame.button, equals(WahooKickrShiftButtons.rightUp));
      expect(frame.pressed, equals(true));
    });
    test('rightUp released', () async {
      final frame = kickrBikeShift.parseShortFrame('000166')!;
      expect(frame.button, equals(WahooKickrShiftButtons.rightUp));
      expect(frame.pressed, equals(false));
    });
    test('rightDown pressed', () async {
      final frame = kickrBikeShift.parseShortFrame('80005E')!;
      expect(frame.button, equals(WahooKickrShiftButtons.rightDown));
      expect(frame.pressed, equals(false));
    });
    test('rightDown released', () async {
      final frame = kickrBikeShift.parseShortFrame('80005E')!;
      expect(frame.button, equals(WahooKickrShiftButtons.rightDown));
      expect(frame.pressed, equals(false));
    });
    test('rightBrake', () async {
      final frame = kickrBikeShift.parseShortFrame('40008F')!;
      expect(frame.button, equals(WahooKickrShiftButtons.rightBrake));
      expect(frame.pressed, equals(true));
    });
    test('leftBrake released', () async {
      final frame = kickrBikeShift.parseShortFrame('010004')!;
      expect(frame.button, equals(WahooKickrShiftButtons.leftBrake));
      expect(frame.pressed, equals(false));
    });
    test('shiftUpLeft', () async {
      final frame = kickrBikeShift.parseShortFrame('10008C')!;
      expect(frame.button, equals(WahooKickrShiftButtons.shiftUpLeft));
      expect(frame.pressed, equals(true));
    });
    test('shiftUpLeft released', () async {
      final frame = kickrBikeShift.parseShortFrame('10000C')!;
      expect(frame.button, equals(WahooKickrShiftButtons.shiftUpLeft));
      expect(frame.pressed, equals(false));
    });
    test('shiftDownLeft', () async {
      final frame = kickrBikeShift.parseShortFrame('080084')!;
      expect(frame.button, equals(WahooKickrShiftButtons.shiftDownLeft));
      expect(frame.pressed, equals(true));
    });
    test('shiftDownLeft released', () async {
      final frame = kickrBikeShift.parseShortFrame('080004')!;
      expect(frame.button, equals(WahooKickrShiftButtons.shiftDownLeft));
      expect(frame.pressed, equals(false));
    });
    test('rightBreak released', () async {
      final frame = kickrBikeShift.parseShortFrame('400001')!;
      expect(frame.button, equals(WahooKickrShiftButtons.rightBrake));
      expect(frame.pressed, equals(false));
    });
  });
}
