import 'package:flutter/foundation.dart';
import 'package:universal_ble/universal_ble.dart';

import 'emulated_ble_platform.dart';
import 'emulation_profile.dart';

/// A live emulated device: its peripheral, profile, decoded write log and the
/// interactive inputs bound to it.
class EmulationSession {
  EmulationSession({required this.profile, required this.peripheral, required this.ble}) {
    profile.onRegistered?.call(ble, peripheral);
    final scripted = peripheral.onWrite;
    peripheral.onWrite = (service, characteristic, value) {
      scripted?.call(service, characteristic, value);
      final decoded = profile.decodeWrite?.call(characteristic.toLowerCase(), value);
      if (decoded != null) writeLog.value = [...writeLog.value, decoded];
    };
    inputs = profile.inputs?.call(this) ?? const [];
  }

  final EmulationProfile profile;
  final FakePeripheral peripheral;
  final FakeUniversalBlePlatform ble;
  final ValueNotifier<List<String>> writeLog = ValueNotifier(const []);
  late final List<EmulatedInput> inputs;

  void notify(String characteristicUuid, List<int> bytes) =>
      ble.notify(peripheral.deviceId, characteristicUuid, bytes);

  void dropConnection() => ble.dropConnection(peripheral.deviceId);

  /// Re-emits the scan result with a different RSSI (drives the signal UI).
  void setRssi(int rssi) {
    final base = peripheral.scanResult;
    ble.updateScanResult(
      BleDevice(
        deviceId: base.deviceId,
        name: peripheral.name,
        rssi: rssi,
        services: base.services,
        manufacturerDataList: base.manufacturerDataList,
      ),
    );
  }
}

/// Owns the emulated peripherals in debug builds. Never attached in release
/// builds, so it stays inert there.
class EmulationManager {
  FakeUniversalBlePlatform? _ble;
  final Map<String, EmulationSession> _sessions = {};

  bool get isAvailable => _ble != null;

  /// The fake platform the emulated peripherals live on. Only valid when
  /// [isAvailable].
  FakeUniversalBlePlatform get ble => _ble!;

  void attach(FakeUniversalBlePlatform ble) => _ble = ble;

  List<EmulationSession> get sessions => _sessions.values.toList();

  EmulationSession start(EmulationProfile profile) {
    final ble = _ble;
    if (ble == null) throw StateError('EmulationManager.attach was never called');
    final peripheral = profile.build();
    final existing = _sessions[peripheral.deviceId];
    if (existing != null) return existing;
    final session = EmulationSession(profile: profile, peripheral: peripheral, ble: ble);
    _sessions[peripheral.deviceId] = session;
    ble.addPeripheral(peripheral);
    return session;
  }

  bool isEmulated(String deviceId) => _sessions.containsKey(deviceId);

  EmulationSession? sessionFor(String deviceId) => _sessions[deviceId];

  void stop(String deviceId) {
    _sessions.remove(deviceId);
    _ble?.removePeripheral(deviceId);
  }

  /// Test hook: drop all sessions (the fake platform's own reset() clears the
  /// peripherals).
  @visibleForTesting
  void reset() => _sessions.clear();
}
