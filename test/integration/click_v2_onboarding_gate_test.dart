import 'dart:async';
import 'dart:typed_data';

import 'package:bike_control/bluetooth/devices/zwift/constants.dart';
import 'package:bike_control/bluetooth/devices/zwift/zwift_clickv2_left_side.dart';
import 'package:bike_control/bluetooth/devices/zwift/zwift_clickv2_right_side.dart';
import 'package:bike_control/bluetooth/emulation/emulated_ble_platform.dart';
import 'package:bike_control/bluetooth/emulation/emulated_peripherals.dart';
import 'package:bike_control/utils/actions/base_actions.dart';
import 'package:bike_control/utils/click_v2_onboarding.dart';
import 'package:bike_control/utils/core.dart';
import 'package:bike_control/utils/keymap/apps/zwift.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prop/prop.dart';

import 'harness/test_env.dart';

/// A GET_RESPONSE for VendorDO.PAGE_DEVICE_PAIRING reporting a not-yet-synced
/// controller -- the branch of ClickLogic.processData that arms (or re-arms)
/// its 59s idle reset timer rather than firing a RESET immediately.
Uint8List _unresolvedPairingPageResponse() {
  final page = DevicePairingDataPage(pairingStatus: ControllerSyncStatus.NOT_CONNECTED.value);
  final response = GetResponse(dataObjectId: VendorDO.PAGE_DEVICE_PAIRING.value, dataObjectData: page.writeToBuffer());
  return Uint8List.fromList([Opcode.GET_RESPONSE.value, ...response.writeToBuffer()]);
}

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

  test('choosing right-side-only writes settings and connects the right side', () async {
    await core.settings.setClickV2OnboardingDone(false);
    await core.settings.setUnlockWithZwift(false);
    await core.settings.setUseNewUnlockMethod(true);

    final right = buildZwiftClickV2(sideCode: ZwiftConstants.CLICK_V2_RIGHT_SIDE);
    env.ble.addPeripheral(right);
    await core.connection.performScanning();
    await IntegrationEnv.waitFor(
      () => core.connection.devices.whereType<ZwiftClickV2RightSide>().isNotEmpty,
      description: 'the Click V2 right side to appear',
    );

    expect(ClickV2Onboarding.pendingDevices, isNotEmpty);

    await ClickV2Onboarding.chooseRightSideOnly();

    expect(core.settings.getUnlockWithZwift(), isFalse);
    expect(core.settings.getClickV2RightSideOnly(), isTrue);
    expect(core.settings.getUseNewUnlockMethod(), isTrue);
    expect(core.settings.getClickV2OnboardingDone(), isTrue);
    expect(ClickV2Onboarding.isPending, isFalse);

    await IntegrationEnv.waitFor(
      () => right.isConnected,
      description: 'the Click V2 right side to connect after the choice',
    );
  });

  // The whole point of the mode: the locked puck stays out. Its restart loop
  // would otherwise fight the right side's handshake over ClickLogic's single
  // shared reset timer.
  test('right-side-only holds the left side out of the connect queue', () async {
    await core.settings.setClickV2OnboardingDone(false);
    await core.settings.setUnlockWithZwift(false);
    await core.settings.setUseNewUnlockMethod(true);

    final left = buildZwiftClickV2(sideCode: ZwiftConstants.CLICK_V2_LEFT_SIDE);
    env.ble.addPeripheral(left);
    await core.connection.performScanning();
    final device = await IntegrationEnv.waitFor(
      () => core.connection.devices.whereType<ZwiftClickV2LeftSide>().isNotEmpty,
      description: 'the Click V2 left side to appear',
    ).then((_) => core.connection.devices.whereType<ZwiftClickV2LeftSide>().first);

    await ClickV2Onboarding.chooseRightSideOnly();

    expect(device.shouldAutoConnect, isFalse);
    // It is still listed -- held back, not forgotten -- so "Set up again" can
    // bring it straight back without a trip through ignored devices.
    expect(core.connection.devices.contains(device), isTrue);

    await core.connection.performScanning();
    expect(left.isConnected, isFalse);
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

  test('right-side-only turns the split representation back on when it was off', () async {
    await core.settings.setClickV2OnboardingDone(false);
    await core.settings.setUnlockWithZwift(false);
    await core.settings.setUseNewUnlockMethod(false);

    // The right side does not exist as its own device in the legacy unified
    // representation, so this mode cannot be honoured without flipping it on.
    await ClickV2Onboarding.chooseRightSideOnly();

    expect(core.settings.getUseNewUnlockMethod(), isTrue);
  });

  // "Set up again" routes through the same chooseRightSideOnly /
  // chooseUnlockWithZwift entry points as first-time onboarding, but reaches
  // them with the left side ALREADY CONNECTED -- a case first-time onboarding
  // never hits (a pending device is by definition disconnected). Switching to
  // right-side-only there has to actually take the left side down, not just
  // write the setting and leave a live link that the new mode says is not
  // part of the setup.
  test('"Set up again" -> right side only drops an already-connected left side', () async {
    // Onboarding already done and settled on Zwift mode -- i.e. the rider is
    // re-visiting the explainer via "Set up again", not doing first-time
    // onboarding.
    await core.settings.setClickV2OnboardingDone(true);
    await core.settings.setUnlockWithZwift(true);
    await core.settings.setClickV2RightSideOnly(false);

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

    await ClickV2Onboarding.chooseRightSideOnly();

    expect(core.settings.getUnlockWithZwift(), isFalse);
    expect(core.settings.getClickV2RightSideOnly(), isTrue);

    await IntegrationEnv.waitFor(
      () => !left.isConnected,
      description: 'the already-connected left side to be dropped by the mode switch',
    );

    // And it stays down: the next scan must not quietly bring it back.
    await core.connection.performScanning();
    expect(left.isConnected, isFalse);
  });

  // FINDING 1 (reset-timer half). ClickLogic._resetTimer is private static
  // state -- a test in this file cannot read "was it cancelled" directly.
  // What IS observable is its side effect: left uncancelled, it fires a
  // RESET write 59s later. The next two tests use fake_async to fast-forward
  // past that window without a real 59s wait, and assert on that write's
  // presence/absence. This proves the practical consequence FINDING 1 cares
  // about (no spurious restart right after picking Zwift mode) but NOT that
  // `ClickLogic.resetTimer()` specifically is what did it, as opposed to some
  // other change that coincidentally also suppresses the write -- that
  // distinction is not observable from outside ClickLogic.
  test('sanity control: an unresolved pairing response arms a reset timer that fires when nothing cancels it', () {
    fakeAsync((async) {
      final peripheral = FakePeripheral(deviceId: 'reset-timer-control', name: 'Zwift Click');
      env.ble.addPeripheral(peripheral);

      ClickLogic.processData(_unresolvedPairingPageResponse(), deviceId: peripheral.deviceId, services: const []);

      async.elapse(const Duration(seconds: 60));

      expect(
        peripheral.writes.any((w) => w.value.isNotEmpty && w.value.first == Opcode.RESET.value),
        isTrue,
        reason: 'the armed 59s idle timer should have fired a RESET with nothing to cancel it',
      );
    });
  });

  test('"Set up again" -> unlock with Zwift cancels a live ClickLogic reset timer', () {
    fakeAsync((async) {
      final peripheral = FakePeripheral(deviceId: 'reset-timer-cancel', name: 'Zwift Click');
      env.ble.addPeripheral(peripheral);

      ClickLogic.processData(_unresolvedPairingPageResponse(), deviceId: peripheral.deviceId, services: const []);

      unawaited(ClickV2Onboarding.chooseUnlockWithZwift());
      async.flushMicrotasks();

      async.elapse(const Duration(seconds: 60));

      expect(
        peripheral.writes.any((w) => w.value.isNotEmpty && w.value.first == Opcode.RESET.value),
        isFalse,
        reason: 'chooseUnlockWithZwift should have cancelled the pending reset timer before it fired',
      );
    });
  });
}
