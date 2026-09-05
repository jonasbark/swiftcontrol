import 'dart:typed_data';

import 'package:bike_control/bluetooth/devices/bluetooth_device.dart';
import 'package:bike_control/services/sensors/ble_sensor_source.dart';
import 'package:bike_control/services/sensors/sensor_quantity.dart';
import 'package:universal_ble/universal_ble.dart';

/// A standards-compliant heart rate strap paired directly to BikeControl.
///
/// Transport only: discover, subscribe, and hand bytes to [source]. The source
/// owns parsing, and the hub above it owns whether this reading is the one the
/// rider actually wants. No buttons: a strap has nothing for the rider to
/// click, so it is registered with an empty [availableButtons] like the other
/// non-controller accessories in this directory.
///
/// `with Accessory`: a strap reacts to nothing and sends nothing a rider binds
/// to a button, same as a Headwind or Climb. Without the mixin, `Connection`
/// remembers it as `RememberedDeviceKind.controller` instead of excluding it
/// the way it does every other accessory, and its settings page renders an
/// empty Button Mapping table.
class BleHeartRateDevice extends BluetoothDevice with Accessory {
  BleHeartRateDevice(super.scanResult) : super(availableButtons: const []) {
    source = BleSensorSource(
      // The device id is stable across restarts, which is what the rider's
      // persisted per-quantity selection is keyed on. The advertised name is
      // not — straps rename themselves after a firmware update.
      id: device.deviceId,
      displayName: device.name ?? 'Heart rate monitor',
      provides: const {SensorQuantity.heartRate},
    );
  }

  late final BleSensorSource source;

  /// A strap must connect only when the rider explicitly asks. Without this,
  /// `Connection.addDevices` pushes every heart rate strap it ever sees into
  /// the auto-connect queue, and most straps only allow a single simultaneous
  /// BLE connection — silently taking the rider's strap away from Zwift,
  /// their bike computer or their watch, for no benefit to them here.
  ///
  /// There is no rider-facing "connect this strap" action yet (a later phase
  /// of this feature), so this is a hard `false` for now rather than a
  /// per-device consent flag like `ProxyDevice.shouldAutoConnect` — the
  /// priority is stopping the silent takeover, not building the pairing UI.
  @override
  bool get shouldAutoConnect => false;

  @override
  Future<void> connect() async {
    // Mirrors ProxyDevice/ZwiftClickV2: stay listed and keep the queue's
    // listener wiring, but open no transport while no rider action exists to
    // ask for one.
    if (!shouldAutoConnect) return;
    await super.connect();
  }

  @override
  Future<void> handleServices(List<BleService> services) async {
    final service = services.firstWhere(
      (e) => e.uuid.toLowerCase() == BleSensorSource.heartRateServiceUuid,
      orElse: () => throw Exception(
        'Service not found: ${BleSensorSource.heartRateServiceUuid}',
      ),
    );
    final characteristic = service.characteristics.firstWhere(
      (e) => e.uuid.toLowerCase() == BleSensorSource.heartRateMeasurementUuid,
      orElse: () => throw Exception(
        'Characteristic not found: ${BleSensorSource.heartRateMeasurementUuid}',
      ),
    );

    await UniversalBle.subscribeNotifications(
      device.deviceId,
      service.uuid,
      characteristic.uuid,
    );
  }

  @override
  Future<void> processCharacteristic(String characteristic, Uint8List bytes) async {
    if (characteristic.toLowerCase() != BleSensorSource.heartRateMeasurementUuid) {
      return;
    }
    source.ingestHeartRateMeasurement(bytes);
  }
}
