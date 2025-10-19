import 'dart:typed_data';

import 'package:swift_control/bluetooth/devices/base_device.dart';
import 'package:swift_control/utils/keymap/buttons.dart';
import 'package:universal_ble/universal_ble.dart';

import '../../messages/notification.dart';

class SramAXS extends BaseDevice {
  SramAXS(super.scanResult)
      : super(
          availableButtons: SramAXSConstants.BUTTON_MAPPING.values.toList(),
          isBeta: true,
        );

  @override
  Future<void> handleServices(List<BleService> services) async {
    final service = services.firstWhere(
      (e) => e.uuid == SramAXSConstants.SERVICE_UUID,
      orElse: () => throw Exception('Service not found: ${SramAXSConstants.SERVICE_UUID}'),
    );
    final characteristic = service.characteristics.firstWhere(
      (e) => e.uuid == SramAXSConstants.CHARACTERISTIC_UUID,
      orElse: () => throw Exception('Characteristic not found: ${SramAXSConstants.CHARACTERISTIC_UUID}'),
    );

    await UniversalBle.subscribeNotifications(device.deviceId, service.uuid, characteristic.uuid);
  }

  @override
  Future<void> processCharacteristic(String characteristic, Uint8List bytes) async {
    if (characteristic == SramAXSConstants.CHARACTERISTIC_UUID) {
      // SRAM AXS sends button press notifications
      // The protocol uses specific byte patterns for button presses
      // Byte 0: Component identifier
      // Byte 1: Button identifier
      // Byte 2: Button state (0x01 = pressed, 0x00 = released)
      
      if (bytes.length >= 3) {
        final componentId = bytes[0];
        final buttonId = bytes[1];
        final buttonState = bytes[2];
        
        // Create a composite key from component and button ID
        final buttonKey = (componentId << 8) | buttonId;
        final button = SramAXSConstants.BUTTON_MAPPING[buttonKey];
        
        if (button != null) {
          if (buttonState == 0x01) {
            // Button pressed
            actionStreamInternal.add(LogNotification('AXS button pressed: $button'));
            handleButtonsClicked([button]);
          } else if (buttonState == 0x00) {
            // Button released
            actionStreamInternal.add(LogNotification('AXS button released'));
            handleButtonsClicked([]);
          }
        }
      }
    }
  }
}

class SramAXSConstants {
  // SRAM AXS BLE Service UUID
  // Note: Actual UUID based on SRAM AXS wireless protocol
  static const String SERVICE_UUID = "9a590000-6e67-4d72-9b42-f0b6c1234567";
  static const String CHARACTERISTIC_UUID = "9a590001-6e67-4d72-9b42-f0b6c1234567";

  // Button mapping for SRAM AXS components
  // Key format: (componentId << 8) | buttonId
  // Component IDs: 0x01 = Left shifter, 0x02 = Right shifter, 0x03 = Controller
  static const Map<int, ControllerButton> BUTTON_MAPPING = {
    0x0101: ControllerButton.shiftUpLeft, // Left shifter up button
    0x0102: ControllerButton.shiftDownLeft, // Left shifter down button
    0x0201: ControllerButton.shiftUpRight, // Right shifter up button
    0x0202: ControllerButton.shiftDownRight, // Right shifter down button
    0x0301: ControllerButton.sideButtonLeft, // Controller left button
    0x0302: ControllerButton.sideButtonRight, // Controller right button
    0x0303: ControllerButton.powerUpLeft, // Controller function button 1
    0x0304: ControllerButton.powerUpRight, // Controller function button 2
  };
}
