import 'dart:io';

import 'package:bike_control/bluetooth/devices/trainer_connection.dart';
import 'package:bike_control/bluetooth/messages/notification.dart';
import 'package:bike_control/gen/l10n.dart';
import 'package:bike_control/utils/actions/base_actions.dart';
import 'package:bike_control/utils/core.dart';
import 'package:bike_control/utils/keymap/buttons.dart';
import 'package:bluetooth_low_energy/bluetooth_low_energy.dart';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

/// Base class for Bluetooth Low Energy (BLE) peripheral emulators.
/// Provides common functionality for peripheral management, service advertising,
/// and connection state handling.
abstract class BluetoothEmulator extends TrainerConnection {
  final _peripheralManager = PeripheralManager();
  bool _isLoading = false;
  bool _isServiceAdded = false;
  bool _isSubscribedToEvents = false;
  Central? _central;

  BluetoothEmulator({
    required super.title,
    required super.supportedActions,
  });

  /// Gets the peripheral manager instance.
  @protected
  PeripheralManager get peripheralManager => _peripheralManager;

  /// Gets whether the emulator is currently loading/initializing.
  bool get isLoading => _isLoading;

  /// Sets the loading state.
  @protected
  set isLoading(bool value) => _isLoading = value;

  /// Gets whether services have been added to the peripheral manager.
  @protected
  bool get isServiceAdded => _isServiceAdded;

  /// Sets whether services have been added.
  @protected
  set isServiceAdded(bool value) => _isServiceAdded = value;

  /// Gets whether event subscriptions are active.
  @protected
  bool get isSubscribedToEvents => _isSubscribedToEvents;

  /// Sets whether event subscriptions are active.
  @protected
  set isSubscribedToEvents(bool value) => _isSubscribedToEvents = value;

  /// Gets the current connected central device.
  @protected
  Central? get central => _central;

  /// Sets the connected central device.
  @protected
  set central(Central? value) => _central = value;

  /// Subscribes to peripheral manager state changes.
  @protected
  void subscribeToStateChanges() {
    _peripheralManager.stateChanged.forEach((state) {
      if (kDebugMode) {
        print('Peripheral manager state: ${state.state}');
      }
    });
  }

  /// Subscribes to connection state changes on Android.
  /// Handles connection and disconnection events.
  @protected
  void subscribeToConnectionStateChanges(VoidCallback? onUpdate) {
    if (!kIsWeb && Platform.isAndroid) {
      _peripheralManager.connectionStateChanged.forEach((state) {
        if (kDebugMode) {
          print('Peripheral connection state: ${state.state} of ${state.central.uuid}');
        }
        if (state.state == ConnectionState.connected) {
          // Override in subclass if needed
        } else if (state.state == ConnectionState.disconnected) {
          handleDisconnection();
          onUpdate?.call();
        }
      });
    }
  }

  /// Handles disconnection events. Can be overridden by subclasses.
  @protected
  void handleDisconnection() {
    _central = null;
    isConnected.value = false;
    core.connection.signalNotification(
      AlertNotification(LogLevel.LOGLEVEL_INFO, AppLocalizations.current.disconnected),
    );
  }

  /// Requests Bluetooth advertise permission on Android.
  /// Returns true if permission is granted, false otherwise.
  @protected
  Future<bool> requestBluetoothAdvertisePermission() async {
    if (!kIsWeb && Platform.isAndroid) {
      final status = await Permission.bluetoothAdvertise.request();
      if (!status.isGranted) {
        if (kDebugMode) {
          print('Bluetooth advertise permission not granted');
        }
        return false;
      }
    }
    return true;
  }

  /// Waits for the peripheral manager to be powered on.
  /// Returns true if powered on, false if cancelled (e.g., by user action).
  @protected
  Future<bool> waitForPoweredOn(bool Function() shouldContinue) async {
    while (_peripheralManager.state != BluetoothLowEnergyState.poweredOn && shouldContinue()) {
      if (kDebugMode) {
        print('Waiting for peripheral manager to be powered on...');
      }
      await Future.delayed(const Duration(seconds: 1));
    }
    return _peripheralManager.state == BluetoothLowEnergyState.poweredOn;
  }

  /// Adds a GATT service to the peripheral manager.
  @protected
  Future<void> addService(GATTService service) async {
    await _peripheralManager.addService(service);
  }

  /// Starts advertising with the given advertisement configuration.
  @protected
  Future<void> startAdvertising(Advertisement advertisement) async {
    await _peripheralManager.startAdvertising(advertisement);
  }

  /// Stops advertising and resets state.
  @protected
  Future<void> stopAdvertising() async {
    await _peripheralManager.stopAdvertising();
    isStarted.value = false;
    isConnected.value = false;
    _isLoading = false;
  }

  /// Notifies a characteristic with the given value to the connected central.
  @protected
  Future<void> notifyCharacteristic(
    Central central,
    GATTCharacteristic characteristic, {
    required Uint8List value,
  }) async {
    await _peripheralManager.notifyCharacteristic(central, characteristic, value: value);
  }

  /// Cleans up resources by stopping advertising and removing services.
  @protected
  void cleanup() {
    _peripheralManager.stopAdvertising();
    _peripheralManager.removeAllServices();
    _isServiceAdded = false;
    _isSubscribedToEvents = false;
    _central = null;
    isConnected.value = false;
    isStarted.value = false;
    _isLoading = false;
  }
}
