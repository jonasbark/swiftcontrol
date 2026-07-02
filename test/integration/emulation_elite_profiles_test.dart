import 'package:bike_control/bluetooth/devices/elite/elite_rizer.dart';
import 'package:bike_control/bluetooth/devices/elite/elite_square.dart';
import 'package:bike_control/bluetooth/devices/elite/elite_sterzo.dart';
import 'package:bike_control/bluetooth/emulation/emulation_profile.dart';
import 'package:bike_control/bluetooth/emulation/profiles/elite_profiles.dart';
import 'package:bike_control/utils/actions/base_actions.dart';
import 'package:bike_control/utils/core.dart';
import 'package:bike_control/utils/keymap/apps/zwift.dart';
import 'package:flutter_test/flutter_test.dart';

import 'harness/test_env.dart';

Future<void> main() async {
  final env = await IntegrationEnv.setUp();
  late StubActions stubActions;

  core.connection.initialize();

  setUp(() async {
    await env.resetState();
    stubActions = StubActions();
    // A connected trainer app is required for these devices' steering
    // buttons to fire: SterzoButtons/RizerButtons.rightSteer map to
    // InGameAction.steerRight, which is `isLongPress: true`
    // (utils/keymap/buttons.dart). With no supportedApp at all,
    // BaseDevice._hasTriggerAction() takes a permissive "assume single
    // click" fallback that only fires on release. Zwift's keymap has no
    // entry for these device-specific steering buttons, so — matching
    // production once a trainer app is connected — they fall into the
    // "no mapped trigger at all" branch, which performs the action
    // immediately on press as a long-press trigger. Elite Square's `A`
    // button doesn't care either way (it presses release explicitly).
    stubActions.supportedApp = Zwift();
    core.actionHandler = stubActions;
    core.emulation.reset();
    core.emulation.attach(env.ble);
  });

  tearDown(() async {
    await env.resetConnection();
  });

  test('Sterzo: challenge handshake completes and steering right fires rightSteer', () async {
    final session = core.emulation.start(eliteSterzoProfile);
    await core.connection.performScanning();
    await IntegrationEnv.waitFor(
      () => core.connection.devices.whereType<EliteSterzo>().isNotEmpty,
      description: 'Sterzo detected',
    );
    // The app requests the challenge with [0x03, 0x10] during handleServices.
    await IntegrationEnv.waitFor(
      () => session.peripheral.writes.any((w) => w.value.length >= 2 && w.value[0] == 0x03 && w.value[1] == 0x10),
      description: 'challenge request write',
    );
    // Challenge answer [0x03, 0x11, ...] follows (code table fetch falls back
    // to [0x96, 0x96] because HTTP is blocked in tests).
    await IntegrationEnv.waitFor(
      () => session.peripheral.writes.any((w) => w.value.length >= 2 && w.value[0] == 0x03 && w.value[1] == 0x11),
      timeout: const Duration(seconds: 5),
      description: 'challenge response write',
    );
    // The app's activation write [0x02, 0x02] follows 1s after the challenge
    // response (EliteSterzo._activateSteeringMeasurements). Wait for it so
    // this pending write doesn't fire after tearDown resets the fake BLE
    // platform's peripherals — which would throw into a *later* test.
    await IntegrationEnv.waitFor(
      () => session.peripheral.writes.any((w) => w.value.length >= 2 && w.value[0] == 0x02 && w.value[1] == 0x02),
      timeout: const Duration(seconds: 3),
      description: 'activation write',
    );

    session.inputs.whereType<EmulatedAction>().firstWhere((a) => a.label.startsWith('Calibrate')).run();
    session.inputs.whereType<EmulatedAction>().firstWhere((a) => a.label.startsWith('Steer right')).run();

    await IntegrationEnv.waitFor(
      () => stubActions.performedActions.any((a) => a.button == SterzoButtons.rightSteer),
      timeout: const Duration(seconds: 3),
      description: 'rightSteer performed',
    );
  });

  test('Square: A button press performs EliteSquareButtons.a', () async {
    final session = core.emulation.start(eliteSquareProfile);
    await core.connection.performScanning();
    await IntegrationEnv.waitFor(
      () => core.connection.devices.whereType<EliteSquare>().isNotEmpty,
      description: 'Square detected',
    );

    final a = session.inputs.whereType<EmulatedButton>().firstWhere((b) => b.label == 'A');
    a.onDown();
    a.onUp();

    await IntegrationEnv.waitFor(() => stubActions.performedActions.isNotEmpty, description: 'square action');
    expect(stubActions.performedActions.map((x) => x.button), contains(EliteSquareButtons.a));
  });

  test('Rizer: steering fires rightSteer and incline writes are logged', () async {
    final session = core.emulation.start(eliteRizerProfile);
    await core.connection.performScanning();
    await IntegrationEnv.waitFor(
      () => core.connection.devices.whereType<EliteRizer>().isNotEmpty,
      description: 'Rizer detected',
    );
    final device = core.connection.devices.whereType<EliteRizer>().first;

    session.inputs.whereType<EmulatedAction>().firstWhere((a) => a.label.startsWith('Calibrate')).run();
    session.inputs.whereType<EmulatedAction>().firstWhere((a) => a.label.startsWith('Steer right')).run();
    await IntegrationEnv.waitFor(
      () => stubActions.performedActions.any((a) => a.button == RizerButtons.rightSteer),
      timeout: const Duration(seconds: 3),
      description: 'rizer rightSteer performed',
    );

    await device.writeInclineRaw(600); // +6.00% → tenths 60 → [0x0a, 0x3c, 0x00]
    await IntegrationEnv.waitFor(
      () => session.peripheral.writes.any(
        (w) => w.value.length == 3 && w.value[0] == 0x0a && w.value[1] == 0x3c && w.value[2] == 0x00,
      ),
      description: 'incline write',
    );
    expect(session.writeLog.value, contains('Set incline 6.0%'));
  });
}
