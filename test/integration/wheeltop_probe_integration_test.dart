import 'dart:async';

import 'package:bike_control/bluetooth/devices/wheeltop/wheeltop_eds.dart';
import 'package:bike_control/bluetooth/devices/wheeltop/wheeltop_probe.dart';
import 'package:bike_control/bluetooth/emulation/emulated_ble_platform.dart';
import 'package:bike_control/bluetooth/emulation/emulated_peripherals.dart';
import 'package:bike_control/utils/actions/base_actions.dart';
import 'package:bike_control/utils/core.dart';
import 'package:bike_control/utils/keymap/apps/zwift.dart';
import 'package:flutter_test/flutter_test.dart';

import 'harness/test_env.dart';

/// The WHEELTOP keepalive-reply probe through the REAL Connection class:
/// candidate writes on connect and per status frame, rotation across
/// reconnects, and the opt-in gate. Only the BLE platform is fake.
Future<void> main() async {
  final env = await IntegrationEnv.setUp();
  late StubActions stubActions;
  Timer? advTimer;

  core.connection.initialize();

  void startAdvertising(FakePeripheral peripheral) {
    advTimer?.cancel();
    advTimer = Timer.periodic(
      const Duration(milliseconds: 40),
      (_) => env.ble.updateScanResult(peripheral.scanResult),
    );
  }

  setUp(() async {
    await env.resetState(prefs: {'wheeltop_probe_enabled': true});
    stubActions = StubActions();
    stubActions.supportedApp = Zwift();
    core.actionHandler = stubActions;
    WheeltopProbe.resetRotation();
  });

  tearDown(() async {
    advTimer?.cancel();
    await env.resetConnection();
  });

  Future<void> waitForConnected() => IntegrationEnv.waitFor(
    () => core.connection.devices.whereType<WheeltopEds>().any((d) => d.isConnected),
    description: 'WheeltopEds to connect',
  );

  test('writes the candidate on connect and again per status frame', () async {
    final pod = buildWheeltopEdsTxLeft();
    env.ble.addPeripheral(pod);
    await core.connection.performScanning();
    await waitForConnected();

    await IntegrationEnv.waitFor(() => pod.writes.isNotEmpty, description: 'initial candidate write');
    final first = pod.writes.first;
    // First candidate: type-echo frame on the stock NUS RX slot 6e400003.
    expect(first.characteristic.toLowerCase(), startsWith('6e400003'));
    expect(first.value, [0x04, 0x36, 0x10, 0x4a]);

    env.ble.notify(pod.deviceId, WheeltopEdsConstants.TX_CHARACTERISTIC_UUID, [0x04, 0x36, 0x10, 0x4a]);
    await IntegrationEnv.waitFor(() => pod.writes.length >= 2, description: 'status-frame reply write');
    expect(pod.writes[1].value, first.value);
    expect(pod.writes[1].characteristic, first.characteristic);
  });

  test('rotation advances to the next candidate on reconnect', () async {
    final pod = buildWheeltopEdsTxLeft();
    env.ble.addPeripheral(pod);
    startAdvertising(pod);
    await core.connection.performScanning();
    await IntegrationEnv.waitFor(() => pod.writes.isNotEmpty, description: 'first cycle write');

    env.ble.dropConnection(pod.deviceId);
    await IntegrationEnv.waitFor(() => pod.writes.length >= 2, description: 'second cycle write');
    // Candidate 2: the ack (code + 1) frame, still on 6e400003.
    expect(pod.writes[1].value, [0x04, 0x36, 0x11, 0x4b]);
    expect(pod.writes[1].characteristic.toLowerCase(), startsWith('6e400003'));
  });

  test('probe stays silent when the experiment is disabled', () async {
    await env.resetState(); // defaults: experiment off
    core.actionHandler = stubActions;

    final pod = buildWheeltopEdsTxLeft();
    env.ble.addPeripheral(pod);
    await core.connection.performScanning();
    await waitForConnected();

    env.ble.notify(pod.deviceId, WheeltopEdsConstants.TX_CHARACTERISTIC_UUID, [0x04, 0x36, 0x10, 0x4a]);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(pod.writes, isEmpty);
  });
}
