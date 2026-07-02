import 'dart:typed_data';

import 'package:universal_ble/universal_ble.dart';

import 'emulated_ble_platform.dart';

/// Splits universal_ble traffic between the real platform backend and the
/// in-memory emulation backend. Devices registered as emulated peripherals
/// route to the fake; everything else passes through untouched. Both
/// children's events are re-emitted through this instance — the one
/// Connection registers its callbacks on.
class RoutingBlePlatform extends UniversalBlePlatform {
  RoutingBlePlatform({required this.real, required this.fake}) {
    _forwardEvents(real);
    _forwardEvents(fake);
  }

  final UniversalBlePlatform real;
  final FakeUniversalBlePlatform fake;

  void _forwardEvents(UniversalBlePlatform child) {
    child.onScanResultUpdate = updateScanResult;
    child.onConnectionChange = updateConnection;
    child.onValueChange = updateCharacteristicValue;
    child.onAvailabilityChange = updateAvailability;
    child.onPairingStateChange = updatePairingState;
  }

  // A forgotten (unregistered) emulated peripheral no longer has a fake
  // entry, but the app can still address it briefly afterwards (Sterzo's
  // 1s-delayed activation write, Connection's disconnect for an unknown
  // device) — those stray calls must still land on the fake, not leak to the
  // real OS BLE stack, so fall back on the id prefix once the lookup misses.
  UniversalBlePlatform _forDevice(String deviceId) =>
      fake.peripherals.containsKey(deviceId) || deviceId.startsWith('emulated:') ? fake : real;

  @override
  Future<AvailabilityState> getBluetoothAvailabilityState() => real.getBluetoothAvailabilityState();

  @override
  Future<bool> enableBluetooth() => real.enableBluetooth();

  @override
  Future<bool> disableBluetooth() => real.disableBluetooth();

  @override
  Future<bool> hasPermissions({bool withAndroidFineLocation = false}) =>
      real.hasPermissions(withAndroidFineLocation: withAndroidFineLocation);

  @override
  Future<void> requestPermissions({bool withAndroidFineLocation = false}) =>
      real.requestPermissions(withAndroidFineLocation: withAndroidFineLocation);

  @override
  Future<void> startScan({ScanFilter? scanFilter, PlatformConfig? platformConfig}) async {
    await fake.startScan(scanFilter: scanFilter, platformConfig: platformConfig);
    try {
      await real.startScan(scanFilter: scanFilter, platformConfig: platformConfig);
    } catch (_) {
      // A dead real radio (Bluetooth off on the dev machine) must not break
      // an emulation session; without emulated peripherals keep the error.
      if (fake.peripherals.isEmpty) rethrow;
    }
  }

  @override
  Future<void> stopScan() async {
    await fake.stopScan();
    try {
      await real.stopScan();
    } catch (_) {
      if (fake.peripherals.isEmpty) rethrow;
    }
  }

  @override
  Future<bool> isScanning() async => (await fake.isScanning()) || (await real.isScanning());

  @override
  Future<void> connect(String deviceId, {Duration? connectionTimeout, bool autoConnect = false}) =>
      _forDevice(deviceId).connect(deviceId, connectionTimeout: connectionTimeout, autoConnect: autoConnect);

  @override
  Future<void> disconnect(String deviceId) => _forDevice(deviceId).disconnect(deviceId);

  @override
  Future<List<BleService>> discoverServices(String deviceId, bool withDescriptors) =>
      _forDevice(deviceId).discoverServices(deviceId, withDescriptors);

  @override
  Future<void> setNotifiable(
    String deviceId,
    String service,
    String characteristic,
    BleInputProperty bleInputProperty,
  ) =>
      _forDevice(deviceId).setNotifiable(deviceId, service, characteristic, bleInputProperty);

  @override
  Future<Uint8List> readValue(String deviceId, String service, String characteristic, {Duration? timeout}) =>
      _forDevice(deviceId).readValue(deviceId, service, characteristic, timeout: timeout);

  @override
  Future<void> writeValue(
    String deviceId,
    String service,
    String characteristic,
    Uint8List value,
    BleOutputProperty bleOutputProperty,
  ) =>
      _forDevice(deviceId).writeValue(deviceId, service, characteristic, value, bleOutputProperty);

  @override
  Future<int> requestMtu(String deviceId, int expectedMtu) => _forDevice(deviceId).requestMtu(deviceId, expectedMtu);

  @override
  Future<int> readRssi(String deviceId) => _forDevice(deviceId).readRssi(deviceId);

  @override
  Future<void> requestConnectionPriority(String deviceId, BleConnectionPriority priority) =>
      _forDevice(deviceId).requestConnectionPriority(deviceId, priority);

  @override
  Future<bool> isPaired(String deviceId) => _forDevice(deviceId).isPaired(deviceId);

  @override
  Future<bool> pair(String deviceId) => _forDevice(deviceId).pair(deviceId);

  @override
  Future<void> unpair(String deviceId) => _forDevice(deviceId).unpair(deviceId);

  @override
  Future<BleConnectionState> getConnectionState(String deviceId) => _forDevice(deviceId).getConnectionState(deviceId);

  @override
  Future<List<BleDevice>> getSystemDevices(List<String>? withServices) => real.getSystemDevices(withServices);
}
