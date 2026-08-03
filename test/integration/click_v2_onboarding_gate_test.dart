import 'package:bike_control/bluetooth/devices/zwift/constants.dart';
import 'package:bike_control/bluetooth/devices/zwift/zwift_clickv2_left_side.dart';
import 'package:bike_control/bluetooth/devices/zwift/zwift_clickv2_right_side.dart';
import 'package:bike_control/bluetooth/emulation/emulated_peripherals.dart';
import 'package:bike_control/utils/actions/base_actions.dart';
import 'package:bike_control/utils/click_v2_onboarding.dart';
import 'package:bike_control/utils/core.dart';
import 'package:bike_control/utils/keymap/apps/zwift.dart';
import 'package:flutter_test/flutter_test.dart';

import 'harness/test_env.dart';

/// The onboarding gate through the REAL Connection class: a discovered Click
/// V2 must reach the device list but open no BLE connection until the rider
/// has picked an unlock mode.
Future<void> main() async {
  final env = await IntegrationEnv.setUp();

  core.connection.initialize();

  setUp(() async {
    await env.resetState();
    final stubActions = StubActions();
    stubActions.supportedApp = Zwift();
    core.actionHandler = stubActions;
  });

  tearDown(() async {
    await env.resetConnection();
  });

  test('a pending Click V2 is listed but never connected', () async {
    await core.settings.setClickV2OnboardingDone(false);
    await core.settings.setUnlockWithZwift(false);

    final left = buildZwiftClickV2(sideCode: ZwiftConstants.CLICK_V2_LEFT_SIDE);
    final right = buildZwiftClickV2(sideCode: ZwiftConstants.CLICK_V2_RIGHT_SIDE);
    env.ble.addPeripheral(left);
    env.ble.addPeripheral(right);

    await core.connection.performScanning();

    await IntegrationEnv.waitFor(
      () =>
          core.connection.devices.whereType<ZwiftClickV2LeftSide>().isNotEmpty &&
          core.connection.devices.whereType<ZwiftClickV2RightSide>().isNotEmpty,
      description: 'both Click V2 sides to appear in the device list',
    );

    final leftDevice = core.connection.devices.whereType<ZwiftClickV2LeftSide>().first;
    final rightDevice = core.connection.devices.whereType<ZwiftClickV2RightSide>().first;

    expect(leftDevice.shouldAutoConnect, isFalse);
    expect(rightDevice.shouldAutoConnect, isFalse);
    expect(leftDevice.isConnected, isFalse);
    expect(rightDevice.isConnected, isFalse);

    // The gate is about the transport, not just the flag: no BLE link was
    // opened and no handshake ran.
    expect(left.isConnected, isFalse);
    expect(right.isConnected, isFalse);
    expect(left.subscriptions, isEmpty);
    expect(right.subscriptions, isEmpty);
    expect(left.writes, isEmpty);
    expect(right.writes, isEmpty);
  });

  test('a Click V2 connects normally once onboarding is done', () async {
    await core.settings.setClickV2OnboardingDone(true);

    final left = buildZwiftClickV2(sideCode: ZwiftConstants.CLICK_V2_LEFT_SIDE);
    env.ble.addPeripheral(left);

    await core.connection.performScanning();

    final device = await IntegrationEnv.waitFor(
      () => core.connection.devices.whereType<ZwiftClickV2LeftSide>().isNotEmpty,
      description: 'the Click V2 left side to appear',
    ).then((_) => core.connection.devices.whereType<ZwiftClickV2LeftSide>().first);

    await IntegrationEnv.waitFor(
      () => device.isConnected,
      description: 'the Click V2 left side to connect',
    );

    expect(left.isConnected, isTrue);
  });

  test('choosing left-side-only writes settings and connects the pending sides', () async {
    await core.settings.setClickV2OnboardingDone(false);
    await core.settings.setUnlockWithZwift(false);
    await core.settings.setUseNewUnlockMethod(true);

    final left = buildZwiftClickV2(sideCode: ZwiftConstants.CLICK_V2_LEFT_SIDE);
    env.ble.addPeripheral(left);
    await core.connection.performScanning();
    await IntegrationEnv.waitFor(
      () => core.connection.devices.whereType<ZwiftClickV2LeftSide>().isNotEmpty,
      description: 'the Click V2 left side to appear',
    );

    expect(ClickV2Onboarding.pendingDevices, isNotEmpty);

    await ClickV2Onboarding.chooseLeftSideOnly();

    expect(core.settings.getUnlockWithZwift(), isFalse);
    expect(core.settings.getUseNewUnlockMethod(), isTrue);
    expect(core.settings.getClickV2OnboardingDone(), isTrue);
    expect(ClickV2Onboarding.isPending, isFalse);

    await IntegrationEnv.waitFor(
      () => left.isConnected,
      description: 'the Click V2 left side to connect after the choice',
    );
  });

  test('choosing unlock-with-Zwift writes settings and connects the pending sides', () async {
    await core.settings.setClickV2OnboardingDone(false);
    await core.settings.setUnlockWithZwift(false);

    final left = buildZwiftClickV2(sideCode: ZwiftConstants.CLICK_V2_LEFT_SIDE);
    env.ble.addPeripheral(left);
    await core.connection.performScanning();
    await IntegrationEnv.waitFor(
      () => core.connection.devices.whereType<ZwiftClickV2LeftSide>().isNotEmpty,
      description: 'the Click V2 left side to appear',
    );

    await ClickV2Onboarding.chooseUnlockWithZwift();

    expect(core.settings.getUnlockWithZwift(), isTrue);
    expect(core.settings.getClickV2OnboardingDone(), isTrue);
    expect(ClickV2Onboarding.isPending, isFalse);

    await IntegrationEnv.waitFor(
      () => left.isConnected,
      description: 'the Click V2 left side to connect after the choice',
    );
  });

  test('left-side-only turns the split representation back on when it was off', () async {
    await core.settings.setClickV2OnboardingDone(false);
    await core.settings.setUnlockWithZwift(false);
    await core.settings.setUseNewUnlockMethod(false);

    await ClickV2Onboarding.chooseLeftSideOnly();

    expect(core.settings.getUseNewUnlockMethod(), isTrue);
  });
}
