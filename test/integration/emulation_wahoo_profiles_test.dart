import 'package:bike_control/bluetooth/devices/wahoo/wahoo_kickr_bike_shift.dart';
import 'package:bike_control/bluetooth/devices/wahoo/wahoo_kickr_climb.dart';
import 'package:bike_control/bluetooth/devices/wahoo/wahoo_kickr_headwind.dart';
import 'package:bike_control/bluetooth/emulation/emulation_profile.dart';
import 'package:bike_control/bluetooth/emulation/profiles/wahoo_profiles.dart';
import 'package:bike_control/utils/actions/base_actions.dart';
import 'package:bike_control/utils/core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'harness/test_env.dart';

Future<void> main() async {
  final env = await IntegrationEnv.setUp();
  late StubActions stubActions;

  core.connection.initialize();

  setUp(() async {
    await env.resetState();
    stubActions = StubActions();
    core.actionHandler = stubActions;
    core.emulation.reset();
    core.emulation.attach(env.ble);
  });

  tearDown(() async {
    await env.resetConnection();
  });

  Future<T> connect<T extends Object>(EmulationProfile profile) async {
    core.emulation.start(profile);
    await core.connection.performScanning();
    await IntegrationEnv.waitFor(
      () => core.connection.devices.whereType<T>().isNotEmpty,
      description: '$T detected',
    );
    return core.connection.devices.whereType<T>().first;
  }

  test('Kickr Bike Shift: shift-up-right press performs shiftUpRight', () async {
    await connect<WahooKickrBikeShift>(wahooKickrBikeShiftProfile);
    final session = core.emulation.sessionFor('emulated:kickr-bike-shift')!;

    final button = session.inputs.whereType<EmulatedButton>().firstWhere((b) => b.label == 'Shift up right');
    button.onDown();
    button.onUp();

    await IntegrationEnv.waitFor(() => stubActions.performedActions.isNotEmpty, description: 'shift action');
    expect(
      stubActions.performedActions.map((a) => a.button),
      contains(WahooKickrShiftButtons.shiftUpRight),
    );
  });

  test('Climb: requests control on connect and logs incline writes', () async {
    final device = await connect<WahooKickrClimb>(wahooKickrClimbProfile);
    final session = core.emulation.sessionFor('emulated:kickr-climb')!;

    await IntegrationEnv.waitFor(
      () => session.peripheral.writes.any((w) => w.value.length == 1 && w.value[0] == 0x67),
      description: 'request-control write',
    );

    await device.writeInclineRaw(500); // +5.00% → [0x66, 0xF4, 0x01]
    await IntegrationEnv.waitFor(
      () => session.peripheral.writes.any(
        (w) => w.value.length == 3 && w.value[0] == 0x66 && w.value[1] == 0xf4 && w.value[2] == 0x01,
      ),
      description: 'incline write',
    );
    expect(session.writeLog.value, contains('Set incline 5.0%'));
  });

  test('Headwind: setSpeed writes manual mode then the speed, both logged', () async {
    final device = await connect<WahooKickrHeadwind>(wahooKickrHeadwindProfile);
    final session = core.emulation.sessionFor('emulated:kickr-headwind')!;

    await device.setSpeed(50);

    await IntegrationEnv.waitFor(
      () => session.peripheral.writes.any((w) => w.value.length == 2 && w.value[0] == 0x02 && w.value[1] == 50),
      description: 'fan speed write',
    );
    expect(session.writeLog.value, contains('Manual mode'));
    expect(session.writeLog.value, contains('Fan speed 50%'));
  });
}
