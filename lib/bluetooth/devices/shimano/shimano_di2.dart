import 'dart:typed_data';

import 'package:swift_control/bluetooth/devices/base_device.dart';
import 'package:swift_control/utils/keymap/buttons.dart';
import 'package:universal_ble/universal_ble.dart';

import '../../messages/notification.dart';

class ShimanoDI2 extends BaseDevice {
  ShimanoDI2(super.scanResult)
      : super(
          availableButtons: ShimanoDI2Constants.BUTTON_MAPPING.values.toList(),
          isBeta: true,
        );

  @override
  Future<void> handleServices(List<BleService> services) async {
    final service = services.firstWhere(
      (e) => e.uuid == ShimanoDI2Constants.SERVICE_UUID,
      orElse: () => throw Exception('Service not found: ${ShimanoDI2Constants.SERVICE_UUID}'),
    );
    final characteristic = service.characteristics.firstWhere(
      (e) => e.uuid == ShimanoDI2Constants.CHARACTERISTIC_UUID,
      orElse: () => throw Exception('Characteristic not found: ${ShimanoDI2Constants.CHARACTERISTIC_UUID}'),
    );

    await UniversalBle.subscribeNotifications(device.deviceId, service.uuid, characteristic.uuid);
  }

  @override
  Future<void> processCharacteristic(String characteristic, Uint8List bytes) async {
    if (characteristic == ShimanoDI2Constants.CHARACTERISTIC_UUID) {
      // DI2 sends button press notifications
      // The protocol uses specific byte patterns for button presses
      // Byte 0: Button identifier
      // Byte 1: Button state (0x01 = pressed, 0x00 = released)
      
      if (bytes.length >= 2) {
        final buttonId = bytes[0];
        final buttonState = bytes[1];
        
        final button = ShimanoDI2Constants.BUTTON_MAPPING[buttonId];
        
        if (button != null) {
          if (buttonState == 0x01) {
            // Button pressed
            actionStreamInternal.add(LogNotification('DI2 button pressed: $button'));
            handleButtonsClicked([button]);
          } else if (buttonState == 0x00) {
            // Button released
            actionStreamInternal.add(LogNotification('DI2 button released'));
            handleButtonsClicked([]);
          }
        }
      }
    }
  }
}

class ShimanoDI2Constants {
  // Shimano DI2 BLE Service UUID (based on ANT+ FE-C protocol)
  // Note: Actual UUID may vary - this is based on common DI2 BLE implementations
  static const String SERVICE_UUID = "6e40fff0-b5a3-f393-e0a9-e50e24dcca9e";
  static const String CHARACTERISTIC_UUID = "6e40fff1-b5a3-f393-e0a9-e50e24dcca9e";

  // Button mapping for DI2 special function buttons
  // These represent the configurable buttons that can be programmed in the DI2 system
  static const Map<int, ControllerButton> BUTTON_MAPPING = {
    0x01: ControllerButton.shiftUpLeft, // Left shifter up button
    0x02: ControllerButton.shiftDownLeft, // Left shifter down button
    0x03: ControllerButton.shiftUpRight, // Right shifter up button
    0x04: ControllerButton.shiftDownRight, // Right shifter down button
    0x05: ControllerButton.sideButtonLeft, // Left function button 1
    0x06: ControllerButton.sideButtonRight, // Right function button 1
    0x07: ControllerButton.powerUpLeft, // Left function button 2
    0x08: ControllerButton.powerUpRight, // Right function button 2
  };
}
