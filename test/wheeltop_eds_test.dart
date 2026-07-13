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

  group('WHEELTOP EDS TX 4-byte frames', () {
    // TX firmware frames observed in the field: 04 | sender type byte |
    // code | additive checksum (sum of the first three bytes, & 0xff).
    Uint8List txPacket(int code, {int type = 0x38}) =>
        Uint8List.fromList([0x04, type, code, (0x04 + type + code) & 0xff]);

    test('top press + release performs one shift up click', () async {
      final device = createDevice(edsType: WheeltopEdsType.txRight);

      await device.processCharacteristic(characteristic, txPacket(0x02));
      await device.processCharacteristic(characteristic, txPacket(0x0a));

      expect(stubActions.performedActions.length, 1);
      expect(
        stubActions.performedActions.single,
        PerformedAction(WheeltopEdsButtons.shiftUp, isDown: true, isUp: true),
      );
    });

    test('hold repeats are ignored like in the 3-byte protocol', () async {
      final device = createDevice(edsType: WheeltopEdsType.txRight);

      await device.processCharacteristic(characteristic, txPacket(0x01));
      await device.processCharacteristic(characteristic, txPacket(0x03));
      await device.processCharacteristic(characteristic, txPacket(0x03));
      await device.processCharacteristic(characteristic, txPacket(0x09));

      expect(stubActions.performedActions.length, 1);
      expect(
        stubActions.performedActions.single,
        PerformedAction(WheeltopEdsButtons.shiftDown, isDown: true, isUp: true),
      );
    });

    test('1 Hz status frame 0x10 performs no action and logs once per connection', () async {
      final device = createDevice(edsType: WheeltopEdsType.txRight);
      final logs = <String>[];
      final sub = device.actionStream.listen((n) => logs.add(n.toString()));

      // The field log shows this exact frame repeating at 1 Hz.
      final status = Uint8List.fromList([0x04, 0x38, 0x10, 0x4c]);
      await device.processCharacteristic(characteristic, status);
      await device.processCharacteristic(characteristic, status);
      await device.processCharacteristic(characteristic, status);
      await Future<void>.delayed(Duration.zero);

      expect(stubActions.performedActions, isEmpty);
      expect(logs.where((l) => l.contains('0x10')).length, 1);

      // A reconnect resets the dedupe so diagnostics reappear per connection.
      device.resetConnectionState();
      await device.processCharacteristic(characteristic, status);
      await Future<void>.delayed(Duration.zero);
      expect(logs.where((l) => l.contains('0x10')).length, 2);

      await sub.cancel();
    });

    test('corrupt or unknown-sender 4-byte frames are invalid and logged once', () async {
      final device = createDevice(edsType: WheeltopEdsType.txRight);
      final logs = <String>[];
      final sub = device.actionStream.listen((n) => logs.add(n.toString()));

      // Wrong checksum, repeated — must not spam the log.
      final corrupt = Uint8List.fromList([0x04, 0x38, 0x10, 0x4d]);
      await device.processCharacteristic(characteristic, corrupt);
      await device.processCharacteristic(characteristic, corrupt);
      // Second byte is not a known sender type byte (checksum valid).
      await device.processCharacteristic(characteristic, Uint8List.fromList([0x04, 0x35, 0x02, 0x3b]));
      await Future<void>.delayed(Duration.zero);

      expect(stubActions.performedActions, isEmpty);
      expect(logs.where((l) => l.contains('0438104d')).length, 1);
      expect(logs.where((l) => l.contains('0435023b')).length, 1);

      await sub.cancel();
    });
  });

  group('WHEELTOP EDS reconnect state reset', () {
    test('resetConnectionState clears stale pressed-button state so the next press fires', () async {
      final device = createDevice();

      // Simulate a mid-hold BLE drop: a press arrives but the connection
      // drops before the release packet, so the button is stuck "pressed".
      await device.processCharacteristic(characteristic, _packet(0x02));
      expect(stubActions.performedActions, isEmpty);

      // disconnect() calls this before reaching the real BLE platform channel
      // (UniversalBle.disconnect throws MissingPluginException in a unit
      // test), so exercise the reset logic it wraps directly.
      device.resetConnectionState();

      // Reconnect, then press the same button again. Without the reset,
      // Set.add would return false (already "pressed") and this press would
      // be silently swallowed, only firing a spurious release later.
      await device.processCharacteristic(characteristic, _packet(0x02));
      await device.processCharacteristic(characteristic, _packet(0x0a));

      expect(stubActions.performedActions.length, 1);
      expect(
        stubActions.performedActions.single,
        PerformedAction(WheeltopEdsButtons.shiftUp, isDown: true, isUp: true),
      );
    });
  });

  group('WHEELTOP EDS notify-capable characteristic selection', () {
    // selectSubscriptionTargets is pure (no BLE platform channel involved),
    // so it is tested directly rather than through handleServices.
    const rxCharacteristic = '6e400003-b5a3-f393-e0a9-e50e24dcca9e';

    test('prefers 6e400002 when it is notify-capable', () {
      final targets = WheeltopEds.selectSubscriptionTargets([
        BleCharacteristic(WheeltopEdsConstants.TX_CHARACTERISTIC_UUID, [CharacteristicProperty.notify], []),
        BleCharacteristic(rxCharacteristic, [CharacteristicProperty.notify], []),
      ]);
      expect(targets, [WheeltopEdsConstants.TX_CHARACTERISTIC_UUID.toLowerCase()]);
    });

    test('falls back to the notify-capable characteristic when 6e400002 is write-only', () {
      // Regression case: a stock Nordic UART layout where 6e400002 exists but
      // is write-only, and notifications actually arrive on 6e400003.
      final targets = WheeltopEds.selectSubscriptionTargets([
        BleCharacteristic(WheeltopEdsConstants.TX_CHARACTERISTIC_UUID, [CharacteristicProperty.write], []),
        BleCharacteristic(rxCharacteristic, [CharacteristicProperty.notify], []),
      ]);
      expect(targets, [rxCharacteristic]);
    });

    test('subscribes to every notify/indicate characteristic when 6e400002 does not qualify', () {
      const otherUuid = '6e400004-b5a3-f393-e0a9-e50e24dcca9e';
      final targets = WheeltopEds.selectSubscriptionTargets([
        BleCharacteristic(WheeltopEdsConstants.TX_CHARACTERISTIC_UUID, [CharacteristicProperty.write], []),
        BleCharacteristic(rxCharacteristic, [CharacteristicProperty.notify], []),
        BleCharacteristic(otherUuid, [CharacteristicProperty.indicate], []),
      ]);
      expect(targets, containsAll([rxCharacteristic, otherUuid]));
      expect(targets, isNot(contains(WheeltopEdsConstants.TX_CHARACTERISTIC_UUID.toLowerCase())));
    });

    test('still attempts 6e400002 when nothing in the service is notify-capable', () {
      final targets = WheeltopEds.selectSubscriptionTargets([
        BleCharacteristic(WheeltopEdsConstants.TX_CHARACTERISTIC_UUID, [CharacteristicProperty.write], []),
      ]);
      expect(targets, [WheeltopEdsConstants.TX_CHARACTERISTIC_UUID.toLowerCase()]);
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

  group('connect-backoff seam', () {
    test('gives up after three attempts with localized guidance', () {
      final device = createDevice(edsType: WheeltopEdsType.txLeft);
      expect(device.maxAutoConnectAttempts, 3);
      expect(device.connectionGuidance, AppLocalizations.current.wheeltopClaimedByDerailleurHint);
    });
  });
}

Uint8List _packet(int opcode) => Uint8List.fromList([0x04, opcode, 0x04 ^ opcode]);
