import 'package:bike_control/bluetooth/devices/zwift/zwift_click.dart';
import 'package:bike_control/bluetooth/emulation/profiles/zwift_profiles.dart';
import 'package:bike_control/utils/actions/base_actions.dart';
import 'package:bike_control/utils/core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'harness/test_env.dart';

Future<void> main() async {
  final env = await IntegrationEnv.setUp();

  core.connection.initialize();

  setUp(() async {
    await env.resetState();
    core.actionHandler = StubActions();
    core.emulation.reset();
    core.emulation.attach(env.ble);
  });

  tearDown(() async {
    await env.resetConnection();
  });

  Future<ZwiftClick> connect() async {
    core.emulation.start(zwiftClickProfile);
    await core.connection.performScanning();
    await IntegrationEnv.waitFor(
      () => core.connection.devices.whereType<ZwiftClick>().isNotEmpty,
      description: 'emulated Zwift Click in device list',
    );
    return core.connection.devices.whereType<ZwiftClick>().first;
  }

  test('forgetting an emulated device unregisters its peripheral', () async {
    final device = await connect();

    await core.connection.disconnect(device, forget: true, persistForget: false);

    expect(core.emulation.isEmulated('emulated:zwift-click'), isFalse);
    expect(env.ble.peripherals, isEmpty);
    expect(core.connection.devices, isEmpty);
  });

  test('the same profile can be re-added after forgetting (scan cache cleared)', () async {
    final device = await connect();
    await core.connection.disconnect(device, forget: true, persistForget: false);

    final again = await connect();

    // `connect()` only waits for the device to appear in the list — the
    // reconnect's own async connect chain (kicked off fire-and-forget by
    // the connection queue) can still be in flight a beat later, so give
    // `isConnected` a moment to catch up.
    await IntegrationEnv.waitFor(() => again.isConnected, description: 'reconnected emulated Zwift Click');
    expect(again.isConnected, isTrue);
  });
}
