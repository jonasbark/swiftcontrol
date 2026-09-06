import 'package:bike_control/bluetooth/devices/bluetooth_device.dart';
import 'package:bike_control/services/sensors/ble_sensor_source.dart';

/// Marks a [BluetoothDevice] as a standards-compliant BLE sensor that owns a
/// [BleSensorSource] — a heart rate strap, a cadence sensor, or a power
/// meter (`BleHeartRateDevice`, `BleCadenceDevice`, `BlePowerDevice`).
///
/// [Connection] and [SensorDiscoverySection] need to reach ANY sensor of
/// this shape without caring which concrete type it is. Before this existed,
/// both were gated on `is! BleHeartRateDevice` specifically — which meant a
/// cadence sensor or power meter could be discovered and classified by
/// `BluetoothDevice.fromScanResult`, but could never actually be connected
/// (the discovery section never listed it) and, even if something else had
/// connected it, its source would never reach `SensorHub` (the registration
/// gate dropped it). A second `is BleCadenceDevice || is BlePowerDevice`
/// check would have papered over that specific gap while leaving the exact
/// same trap for the next sensor type; a shared interface does not.
mixin BleSensorDevice on BluetoothDevice {
  /// The source this device feeds. Parsing and hub registration live on the
  /// source; this device is transport only (connect, subscribe, hand bytes
  /// off) — see the source's own doc comment.
  BleSensorSource get source;
}
