import 'package:bike_control/bluetooth/devices/sram/sram_axs.dart';
import 'package:bike_control/utils/actions/base_actions.dart';
import 'package:bike_control/utils/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:universal_ble/universal_ble.dart';

SramAxs _device() => SramAxs(BleDevice(deviceId: 'dev1', name: 'SRAM 42'));

void main() {
  // Constructing a BluetoothDevice touches `core.actionHandler` (BaseDevice's
  // constructor checks `supportedApp`), so it must be initialized before any
  // test builds a SramAxs, even though `logicalButtonName` itself is pure.
  // `logicalButtonName` never touches `core.settings`, so unlike other device
  // tests (e.g. test/shimano_di2_test.dart) we don't need `core.settings.init()`.
  core.actionHandler = StubActions();

  test('names a decoded paddle press by shifter, in first-seen order', () {
    final d = _device();
    // First unique serial → "Shifter A"; paddle mask (1) → "Paddle".
    expect(d.logicalButtonName(100, 1), 'SRAM Shifter A – Paddle');
    // Second serial → "Shifter B".
    expect(d.logicalButtonName(200, 1), 'SRAM Shifter B – Paddle');
  });

  test('degraded press (mask null) names by serial only', () {
    final d = _device();
    expect(d.logicalButtonName(100, null), 'SRAM Shifter A');
  });

  test('button decoded before the serial arrives gets a shifter-less label (no double space)', () {
    final d = _device();
    final name = d.logicalButtonName(null, 1);
    expect(name, 'SRAM Paddle');
    expect(name.contains('  '), isFalse);
  });

  test('fully anonymous press falls back to the legacy label', () {
    final d = _device();
    expect(d.logicalButtonName(null, null), 'SRAM Button');
  });

  test('stored -1 sentinels re-register as the degraded label, not Button 0x-1', () {
    final d = _device();
    expect(d.storedButtonName(100, -1), 'SRAM Shifter A');
    expect(d.storedButtonName(-1, -1), 'SRAM Button');
  });
}
