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
/// auto-arming on the first status frame, answering each frame, rotation
/// across reconnects, and the opt-out gate. Only the BLE platform is fake.
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

  const txChar = WheeltopEdsConstants.TX_CHARACTERISTIC_UUID;
  // TX Left (type 0x36) status frame: 04 36 10 sum, sum = 0x4a.
  final statusFrame = [0x04, 0x36, 0x10, 0x4a];

  Future<void> waitSubscribed(FakePeripheral pod) => IntegrationEnv.waitFor(
    () => pod.subscriptions.contains(txChar.toLowerCase()),
    description: 'WheeltopEds to connect and subscribe',
  );

  test('arms on the first status frame and answers every frame', () async {
    final pod = buildWheeltopEdsTxLeft();
    env.ble.addPeripheral(pod);
    await core.connection.performScanning();
    await waitSubscribed(pod);

    // Nothing is written just from connecting — the probe waits for a frame.
    expect(pod.writes, isEmpty);

    env.ble.notify(pod.deviceId, txChar, statusFrame);
    await IntegrationEnv.waitFor(() => pod.writes.isNotEmpty, description: 'arm + answer first frame');
    final first = pod.writes.first;
    // First candidate: type-echo frame on the stock NUS RX slot 6e400003.
    expect(first.characteristic.toLowerCase(), startsWith('6e400003'));
    expect(first.value, [0x04, 0x36, 0x10, 0x4a]);

    env.ble.notify(pod.deviceId, txChar, statusFrame);
    await IntegrationEnv.waitFor(() => pod.writes.length >= 2, description: 'answer second frame');
    expect(pod.writes[1].value, first.value);
    expect(pod.writes[1].characteristic, first.characteristic);
  });

  test('rotation advances to the next candidate on the next connection', () async {
    final pod = buildWheeltopEdsTxLeft();

    // Connection 1: one status frame → candidate 1.
    env.ble.addPeripheral(pod);
    await core.connection.performScanning();
    await waitSubscribed(pod);
    env.ble.notify(pod.deviceId, txChar, statusFrame);
    await IntegrationEnv.waitFor(() => pod.writes.isNotEmpty, description: 'first candidate');
    expect(pod.writes.first.value, [0x04, 0x36, 0x10, 0x4a]);

    // Drop and wait for the device to be fully torn down, so the next write
    // can only come from a fresh connection's probe.
    final writesAfterFirst = pod.writes.length;
    env.ble.dropConnection(pod.deviceId);
    await IntegrationEnv.waitFor(
      () => core.connection.devices.whereType<WheeltopEds>().isEmpty,
      description: 'first connection torn down',
    );

    // Connection 2: re-advertise, reconnect, answer with the next candidate.
    startAdvertising(pod);
    await IntegrationEnv.waitFor(
      () {
        if (core.connection.devices.whereType<WheeltopEds>().any((d) => d.isConnected)) {
          env.ble.notify(pod.deviceId, txChar, statusFrame);
        }
        return pod.writes.length > writesAfterFirst;
      },
      timeout: const Duration(seconds: 8),
      description: 'second candidate after reconnect',
    );
    // Candidate 2: the ack (code + 1) frame, still on 6e400003.
    expect(pod.writes[writesAfterFirst].value, [0x04, 0x36, 0x11, 0x4b]);
    expect(pod.writes[writesAfterFirst].characteristic.toLowerCase(), startsWith('6e400003'));
  });

  test('captures a reply that arrives on the second NUS slot (6e400003)', () async {
    final pod = buildWheeltopEdsTxLeft();
    env.ble.addPeripheral(pod);
    await core.connection.performScanning();
    // Subscribe-all means the app also subscribes to 6e400003.
    await IntegrationEnv.waitFor(
      () => pod.subscriptions.contains('6e400003-b5a3-f393-e0a9-e50e24dcca9e'),
      description: 'subscribed to the second slot',
    );

    final logs = <String>[];
    final logSub = core.connection.actionStream.listen((n) => logs.add(n.toString()));

    // Arm the probe, then have the pod reply on 6e400003 (a frame we can't parse).
    env.ble.notify(pod.deviceId, txChar, statusFrame);
    await IntegrationEnv.waitFor(() => pod.writes.isNotEmpty, description: 'probe armed');
    env.ble.notify(pod.deviceId, '6e400003-b5a3-f393-e0a9-e50e24dcca9e', [0x04, 0x38, 0x20, 0x5c]);

    await IntegrationEnv.waitFor(
      () => logs.any((l) => l.contains('rx 6e400003') && l.contains('04 38 20 5c')),
      description: 'reply on 6e400003 captured with slot and bytes',
    );
    await logSub.cancel();
  });

  test('does nothing when the experiment is disabled', () async {
    await env.resetState(prefs: {'wheeltop_probe_enabled': false});
    core.actionHandler = stubActions;

    final pod = buildWheeltopEdsTxLeft();
    env.ble.addPeripheral(pod);
    await core.connection.performScanning();
    await waitSubscribed(pod);

    env.ble.notify(pod.deviceId, txChar, statusFrame);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(pod.writes, isEmpty);
  });
}
