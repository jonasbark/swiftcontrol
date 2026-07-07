import 'dart:typed_data';

import 'package:bike_control/bluetooth/devices/wheeltop/wheeltop_eds.dart';
import 'package:bike_control/gen/l10n.dart';
import 'package:bike_control/utils/actions/base_actions.dart';
import 'package:bike_control/utils/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:universal_ble/universal_ble.dart';

void main() async {
  await AppLocalizations.load(const Locale('en'));

  const characteristic = WheeltopEdsConstants.TX_CHARACTERISTIC_UUID;

  WheeltopEds createDevice({WheeltopEdsType edsType = WheeltopEdsType.ox}) =>
      WheeltopEds(BleDevice(deviceId: 'deviceId', name: null), edsType: edsType);

  late StubActions stubActions;

  setUp(() {
    core.actionHandler = StubActions();
    stubActions = core.actionHandler as StubActions;
  });

  group('WHEELTOP EDS button protocol', () {
    test('top press + release performs one shift up click', () async {
      final device = createDevice();

      await device.processCharacteristic(characteristic, _packet(0x02));
      // The click fires on release (BaseDevice single-click semantics).
      expect(stubActions.performedActions, isEmpty);

      await device.processCharacteristic(characteristic, _packet(0x0a));
      expect(stubActions.performedActions.length, 1);
      expect(
        stubActions.performedActions.single,
        PerformedAction(WheeltopEdsButtons.shiftUp, isDown: true, isUp: true),
      );
    });

    test('bottom press + release performs one shift down click', () async {
      final device = createDevice();

      await device.processCharacteristic(characteristic, _packet(0x01));
      await device.processCharacteristic(characteristic, _packet(0x09));

      expect(stubActions.performedActions.length, 1);
      expect(
        stubActions.performedActions.single,
        PerformedAction(WheeltopEdsButtons.shiftDown, isDown: true, isUp: true),
      );
    });

    test('device hold-repeat opcodes are ignored', () async {
      final device = createDevice();

      await device.processCharacteristic(characteristic, _packet(0x01));
      // The shifter repeats these every ~500 ms while held; BaseDevice's own
      // long-press machinery is the single source of hold behavior.
      await device.processCharacteristic(characteristic, _packet(0x03));
      await device.processCharacteristic(characteristic, _packet(0x03));
      await device.processCharacteristic(characteristic, _packet(0x09));

      expect(stubActions.performedActions.length, 1);
      expect(
        stubActions.performedActions.single,
        PerformedAction(WheeltopEdsButtons.shiftDown, isDown: true, isUp: true),
      );
    });

    test('duplicate press packets do not double-fire', () async {
      final device = createDevice();

      await device.processCharacteristic(characteristic, _packet(0x02));
      await device.processCharacteristic(characteristic, _packet(0x02));
      await device.processCharacteristic(characteristic, _packet(0x0a));

      expect(stubActions.performedActions.length, 1);
    });

    test('T-mode press + release drives the fine-tune button', () async {
      final device = createDevice();

      // Slide switch on "T": top button sends 0x06, release is the shared 0x0a.
      await device.processCharacteristic(characteristic, _packet(0x06));
      await device.processCharacteristic(characteristic, _packet(0x0a));

      expect(stubActions.performedActions.length, 1);
      expect(
        stubActions.performedActions.single,
        PerformedAction(WheeltopEdsButtons.fineTuneUp, isDown: true, isUp: true),
      );
    });

    test('T-mode bottom press + release drives the fine-tune down button', () async {
      final device = createDevice();

      await device.processCharacteristic(characteristic, _packet(0x05));
      await device.processCharacteristic(characteristic, _packet(0x09));

      expect(stubActions.performedActions.length, 1);
      expect(
        stubActions.performedActions.single,
        PerformedAction(WheeltopEdsButtons.fineTuneDown, isDown: true, isUp: true),
      );
    });

    test('invalid packets perform no actions', () async {
      final device = createDevice();

      // Wrong checksum.
      await device.processCharacteristic(characteristic, Uint8List.fromList([0x04, 0x01, 0x00]));
      // Wrong length.
      await device.processCharacteristic(characteristic, Uint8List.fromList([0x04, 0x01]));
      await device.processCharacteristic(characteristic, Uint8List.fromList([0x04, 0x01, 0x05, 0x00]));
      // Wrong prefix (checksum valid for prefix 0x05).
      await device.processCharacteristic(characteristic, Uint8List.fromList([0x05, 0x01, 0x04]));
      // Unknown opcode with valid checksum.
      await device.processCharacteristic(characteristic, Uint8List.fromList([0x04, 0x0b, 0x0f]));
      // Releases without a prior press.
      await device.processCharacteristic(characteristic, _packet(0x09));
      await device.processCharacteristic(characteristic, _packet(0x0a));

      expect(stubActions.performedActions, isEmpty);
    });

    test('both buttons pressed together click both, remaining hold clicks once more', () async {
      final device = createDevice();

      await device.processCharacteristic(characteristic, _packet(0x01));
      expect(stubActions.performedActions, isEmpty);

      // Second button joins -> multi-button branch clicks both immediately
      // (the front-shift combo is inactive without a connected trainer proxy).
      await device.processCharacteristic(characteristic, _packet(0x02));
      expect(stubActions.performedActions.length, 2);

      // Releasing one leaves the other pressed; the framework treats it as a
      // fresh single press, so its click fires on the final release — the same
      // semantics as other multi-button controllers in the app.
      await device.processCharacteristic(characteristic, _packet(0x09));
      expect(stubActions.performedActions.length, 2);

      await device.processCharacteristic(characteristic, _packet(0x0a));
      expect(stubActions.performedActions.length, 3);
      expect(
        stubActions.performedActions.last,
        PerformedAction(WheeltopEdsButtons.shiftUp, isDown: true, isUp: true),
      );
    });
  });

  group('WHEELTOP EDS identity', () {
    test('name derives from the variant', () {
      expect(createDevice().name, 'WHEELTOP EDS OX');
      expect(createDevice(edsType: WheeltopEdsType.txLeft).name, 'WHEELTOP EDS TX Left');
      expect(createDevice(edsType: WheeltopEdsType.txRight).name, 'WHEELTOP EDS TX Right');
      expect(createDevice(edsType: WheeltopEdsType.txFront).name, 'WHEELTOP EDS TX Front');
    });

    test('variant maps from the advertisement type byte', () {
      expect(WheeltopEdsType.fromTypeByte(0x37), WheeltopEdsType.ox);
      expect(WheeltopEdsType.fromTypeByte(0x39), WheeltopEdsType.txFront);
      expect(WheeltopEdsType.fromTypeByte(0x36), WheeltopEdsType.txLeft);
      expect(WheeltopEdsType.fromTypeByte(0x38), WheeltopEdsType.txRight);
      expect(WheeltopEdsType.fromTypeByte(0x99), isNull);
    });

    test('is beta and allows multiple units', () {
      final device = createDevice();
      expect(device.isBeta, isTrue);
      // allowMultiple stamps each unit's deviceId onto its button copies so a
      // TX left+right pair keeps distinct keymap entries.
      expect(device.availableButtons.first.sourceDeviceId, 'deviceId');
      expect(device.availableButtons.length, 4);
    });
  });
}

Uint8List _packet(int opcode) => Uint8List.fromList([0x04, opcode, 0x04 ^ opcode]);
