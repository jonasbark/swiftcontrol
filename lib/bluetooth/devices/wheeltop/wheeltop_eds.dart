import 'dart:typed_data';

import 'package:bike_control/bluetooth/messages/notification.dart';
import 'package:bike_control/utils/keymap/buttons.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:universal_ble/universal_ble.dart';

import '../bluetooth_device.dart';

/// Variant of a WHEELTOP EDS shifter, taken from the type byte in its
/// advertisement. All variants speak the identical button protocol.
enum WheeltopEdsType {
  ox('OX'),
  txFront('TX Front'),
  txLeft('TX Left'),
  txRight('TX Right');

  const WheeltopEdsType(this.label);

  final String label;

  static WheeltopEdsType? fromTypeByte(int byte) => switch (byte) {
    0x37 => WheeltopEdsType.ox,
    0x39 => WheeltopEdsType.txFront,
    0x36 => WheeltopEdsType.txLeft,
    0x38 => WheeltopEdsType.txRight,
    _ => null,
  };
}

/// WHEELTOP EDS wireless shifter (OX / TX family).
///
/// The shifter is a BLE peripheral exposing a Nordic-UART-style service. It
/// has two physical buttons (top / bottom) and a slide switch: position "R"
/// sends the normal shift opcodes, position "T" sends distinct fine-tune
/// opcodes — surfaced here as two extra assignable buttons. The shifter has
/// no gear awareness; it only reports button state.
class WheeltopEds extends BluetoothDevice {
  WheeltopEds(
    super.scanResult, {
    required this.edsType,
    this.batteryCentivolts,
    String? advertisedFirmware,
  }) : super(
         availableButtons: WheeltopEdsButtons.values,
         allowMultiple: true,
         isBeta: true,
       ) {
    firmwareVersion = advertisedFirmware;
  }

  final WheeltopEdsType edsType;

  /// Battery voltage from the advertisement, in volts * 100 (e.g. 292 = 2.92 V).
  final int? batteryCentivolts;

  /// The shifter advertises no usable BLE name.
  @override
  String get name => 'WHEELTOP EDS ${edsType.label}';

  final Set<ControllerButton> _pressedButtons = {};
  final Set<String> _subscribedCharacteristics = {};

  @override
  Future<void> handleServices(List<BleService> services) async {
    final service = services.firstWhere(
      (e) => e.uuid.toLowerCase() == WheeltopEdsConstants.SERVICE_UUID.toLowerCase(),
      orElse: () => throw Exception('Service not found: ${WheeltopEdsConstants.SERVICE_UUID}'),
    );

    // Button events are notified on 6e400002 (the slot standard NUS uses for
    // writes). Prefer it, but fall back to every characteristic of the
    // service in case a firmware notifies elsewhere — the strict packet
    // validation makes stray notifications harmless.
    final preferred = service.characteristics
        .where((c) => c.uuid.toLowerCase() == WheeltopEdsConstants.TX_CHARACTERISTIC_UUID.toLowerCase())
        .toList();
    final targets = preferred.isNotEmpty ? preferred : service.characteristics;
    for (final characteristic in targets) {
      try {
        await UniversalBle.subscribeNotifications(device.deviceId, service.uuid, characteristic.uuid);
        _subscribedCharacteristics.add(characteristic.uuid.toLowerCase());
      } catch (e, st) {
        actionStreamInternal.add(
          LogNotification('WHEELTOP EDS: could not subscribe to ${characteristic.uuid}: $e\n$st'),
        );
      }
    }
  }

  @override
  Future<void> processCharacteristic(String characteristic, Uint8List bytes) async {
    final uuid = characteristic.toLowerCase();
    if (uuid != WheeltopEdsConstants.TX_CHARACTERISTIC_UUID.toLowerCase() &&
        !_subscribedCharacteristics.contains(uuid)) {
      return;
    }

    if (bytes.length != 3 || bytes[0] != WheeltopEdsConstants.PACKET_PREFIX || bytes[2] != (bytes[0] ^ bytes[1])) {
      actionStreamInternal.add(
        LogNotification(
          'WHEELTOP EDS: invalid packet: ${bytes.map((e) => e.toRadixString(16).padLeft(2, '0')).join()}',
        ),
      );
      return;
    }

    switch (bytes[1]) {
      case WheeltopEdsConstants.OPCODE_BOTTOM_PRESSED:
        await _press(availableButtons[WheeltopEdsButtons.indexShiftDown]);
      case WheeltopEdsConstants.OPCODE_TOP_PRESSED:
        await _press(availableButtons[WheeltopEdsButtons.indexShiftUp]);
      case WheeltopEdsConstants.OPCODE_BOTTOM_PRESSED_FINE_TUNE:
        await _press(availableButtons[WheeltopEdsButtons.indexFineTuneDown]);
      case WheeltopEdsConstants.OPCODE_TOP_PRESSED_FINE_TUNE:
        await _press(availableButtons[WheeltopEdsButtons.indexFineTuneUp]);
      case WheeltopEdsConstants.OPCODE_BOTTOM_HELD:
      case WheeltopEdsConstants.OPCODE_TOP_HELD:
      case WheeltopEdsConstants.OPCODE_BOTTOM_HELD_FINE_TUNE:
      case WheeltopEdsConstants.OPCODE_TOP_HELD_FINE_TUNE:
        // The shifter repeats these every ~500 ms while a button is held.
        // BaseDevice's long-press machinery already derives hold behavior
        // from the press/release events, so the device repeats are dropped.
        break;
      case WheeltopEdsConstants.OPCODE_BOTTOM_RELEASED:
        await _release([
          availableButtons[WheeltopEdsButtons.indexShiftDown],
          availableButtons[WheeltopEdsButtons.indexFineTuneDown],
        ]);
      case WheeltopEdsConstants.OPCODE_TOP_RELEASED:
        await _release([
          availableButtons[WheeltopEdsButtons.indexShiftUp],
          availableButtons[WheeltopEdsButtons.indexFineTuneUp],
        ]);
      default:
        actionStreamInternal.add(
          LogNotification(
            'WHEELTOP EDS: unknown opcode 0x${bytes[1].toRadixString(16).padLeft(2, '0')}',
          ),
        );
    }
  }

  Future<void> _press(ControllerButton button) async {
    if (_pressedButtons.add(button)) {
      await handleButtonsClicked(_pressedButtons.toList());
    }
  }

  /// A release opcode is shared between R- and T-mode, so both logical
  /// buttons of the physical button are cleared.
  Future<void> _release(List<ControllerButton> buttons) async {
    var changed = false;
    for (final button in buttons) {
      changed = _pressedButtons.remove(button) || changed;
    }
    if (changed) {
      await handleButtonsClicked(_pressedButtons.toList());
    }
  }
}

class WheeltopEdsConstants {
  // Nordic UART Service.
  static const String SERVICE_UUID = '6e400001-b5a3-f393-e0a9-e50e24dcca9e';

  // Button events are notified here.
  static const String TX_CHARACTERISTIC_UUID = '6e400002-b5a3-f393-e0a9-e50e24dcca9e';

  /// Constant first 7 bytes of the manufacturer-data advertisement.
  static const List<int> ADV_PREFIX = [0x07, 0x0f, 0x00, 0x14, 0x55, 0x6a, 0x84];

  // Offsets into the full advertisement bytes (prefix included).
  static const int ADV_TYPE_INDEX = 7;
  static const int ADV_FIRMWARE_INDEX = 8; // 2 bytes: major, minor
  static const int ADV_BATTERY_INDEX = 10; // 2 bytes big-endian: volts * 100

  static const int PACKET_PREFIX = 0x04;

  static const int OPCODE_BOTTOM_PRESSED = 0x01;
  static const int OPCODE_TOP_PRESSED = 0x02;
  static const int OPCODE_BOTTOM_HELD = 0x03;
  static const int OPCODE_TOP_HELD = 0x04;
  static const int OPCODE_BOTTOM_PRESSED_FINE_TUNE = 0x05;
  static const int OPCODE_TOP_PRESSED_FINE_TUNE = 0x06;
  static const int OPCODE_BOTTOM_HELD_FINE_TUNE = 0x07;
  static const int OPCODE_TOP_HELD_FINE_TUNE = 0x08;
  static const int OPCODE_BOTTOM_RELEASED = 0x09;
  static const int OPCODE_TOP_RELEASED = 0x0a;
}

class WheeltopEdsButtons {
  static const ControllerButton shiftUp = ControllerButton(
    'edsShiftUp',
    action: InGameAction.shiftUp,
    icon: LucideIcons.chevronUp,
  );

  static const ControllerButton shiftDown = ControllerButton(
    'edsShiftDown',
    action: InGameAction.shiftDown,
    icon: LucideIcons.chevronDown,
  );

  /// Sent when the slide switch is in the "T" (fine-tune) position — two
  /// spare buttons with no default action.
  static const ControllerButton fineTuneUp = ControllerButton(
    'edsFineTuneUp',
    icon: LucideIcons.chevronsUp,
  );

  static const ControllerButton fineTuneDown = ControllerButton(
    'edsFineTuneDown',
    icon: LucideIcons.chevronsDown,
  );

  static const List<ControllerButton> values = [shiftUp, shiftDown, fineTuneUp, fineTuneDown];

  static const int indexShiftUp = 0;
  static const int indexShiftDown = 1;
  static const int indexFineTuneUp = 2;
  static const int indexFineTuneDown = 3;
}
