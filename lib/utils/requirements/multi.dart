import 'package:dartx/dartx.dart';
import 'package:flutter/material.dart';
import 'package:keypress_simulator/keypress_simulator.dart';
import 'package:swift_control/pages/scan.dart';
import 'package:swift_control/utils/requirements/platform.dart';
import 'package:universal_ble/universal_ble.dart';

import '../../main.dart';
import '../keymap/keymap.dart';

class KeyboardRequirement extends PlatformRequirement {
  KeyboardRequirement() : super('Keyboard access');

  @override
  Future<void> call() async {
    await keyPressSimulator.requestAccess();
  }

  @override
  Future<void> getStatus() async {
    status = await keyPressSimulator.isAccessAllowed();
  }
}

class KeymapRequirement extends PlatformRequirement {
  KeymapRequirement() : super('Select your Keymap / App');

  @override
  Future<void> call() async {}

  @override
  Future<void> getStatus() async {
    status = actionHandler.keymap != null;
  }

  @override
  Widget? build(BuildContext context, VoidCallback onUpdate) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16.0),
      child: DropdownMenu<Keymap>(
        dropdownMenuEntries:
            Keymap.values.map((key) => DropdownMenuEntry<Keymap>(value: key, label: key.name.capitalize())).toList(),
        onSelected: (keymap) {
          actionHandler.init(keymap);
          onUpdate();
        },
        initialSelection: null,
        hintText: 'Keymap',
      ),
    );
  }
}

class BluetoothTurnedOn extends PlatformRequirement {
  BluetoothTurnedOn() : super('Bluetooth turned on');

  @override
  Future<void> call() async {
    await UniversalBle.enableBluetooth();
  }

  @override
  Future<void> getStatus() async {
    final currentState = await UniversalBle.getBluetoothAvailabilityState();
    status = currentState == AvailabilityState.poweredOn;
  }
}

class UnsupportedPlatform extends PlatformRequirement {
  UnsupportedPlatform() : super('Unsupported platform :(') {
    status = false;
  }

  @override
  Future<void> call() async {}

  @override
  Future<void> getStatus() async {}
}

class BluetoothScanning extends PlatformRequirement {
  BluetoothScanning() : super('Bluetooth Scanning') {
    status = false;
  }

  @override
  Future<void> call() async {}

  @override
  Future<void> getStatus() async {}

  @override
  Widget? build(BuildContext context, VoidCallback onUpdate) {
    return ScanWidget();
  }
}
