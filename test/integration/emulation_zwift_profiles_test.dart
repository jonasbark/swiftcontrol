import 'package:bike_control/bluetooth/devices/bluetooth_device.dart';
import 'package:bike_control/bluetooth/devices/zwift/constants.dart';
import 'package:bike_control/bluetooth/devices/zwift/zwift_clickv2_left_side.dart';
import 'package:bike_control/bluetooth/devices/zwift/zwift_clickv2_right_side.dart';
import 'package:bike_control/bluetooth/devices/zwift/zwift_play.dart';
import 'package:bike_control/bluetooth/devices/zwift/zwift_play_fw2.dart';
import 'package:bike_control/bluetooth/emulation/emulation_profile.dart';
import 'package:bike_control/bluetooth/emulation/profiles/zwift_profiles.dart';
import 'package:bike_control/utils/actions/base_actions.dart';
import 'package:bike_control/utils/core.dart';
import 'package:bike_control/utils/keymap/apps/zwift.dart';
import 'package:bike_control/utils/keymap/buttons.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prop/prop.dart' show propPrefs;

import 'harness/test_env.dart';

Future<void> main() async {
  final env = await IntegrationEnv.setUp();
  late StubActions stubActions;

  core.connection.initialize();

  setUp(() async {
    await env.resetState();
    // ZwiftClickV2 (and thus its left/right sides) reads `propPrefs` — a
    // separate global from the `prop` package — on every button click
    // (isLikelyUnlocked). IntegrationEnv.resetState() only wires up
    // core.settings.prefs, not this second prefs instance (only
    // Settings.init(), which production startup calls but the harness
    // doesn't, does that). Initialize it here so Click V2 button presses
    // don't hit a LateInitializationError.
    propPrefs.initialize(core.settings.prefs);
    // These tests exercise a *connected* Click V2's button/profile behaviour;
    // the unlock-mode onboarding gate (ClickV2Onboarding.isPending) is
    // orthogonal to that. env.resetState() starts from empty prefs, so
    // isPending would otherwise read true and ZwiftClickV2.shouldAutoConnect
    // would hold the controller out of the connect queue -- connect() returns
    // early, no BLE link opens, and the handshake write these tests wait for
    // never arrives. Mark onboarding done so the gate doesn't interfere.
    await core.settings.setClickV2OnboardingDone(true);
    stubActions = StubActions();
    stubActions.supportedApp = Zwift();
    core.actionHandler = stubActions;
    core.emulation.reset();
    core.emulation.attach(env.ble);
  });

  tearDown(() async {
    await env.resetConnection();
  });

  /// Starts [profile], waits for detection as [T] and for the handshake write.
  Future<EmulatedButton> connectAndFirstButton<T extends BluetoothDevice>(
    EmulationProfile profile,
    String deviceId, {
    String? buttonLabel,
  }) async {
    final session = core.emulation.start(profile);
    await core.connection.performScanning();
    await IntegrationEnv.waitFor(
      () => core.connection.devices.whereType<T>().isNotEmpty,
      description: '$T in device list',
    );
    await IntegrationEnv.waitFor(
      () => session.peripheral.writes.isNotEmpty,
      description: '$T handshake write',
    );
    final buttons = session.inputs.whereType<EmulatedButton>();
    return buttonLabel == null ? buttons.first : buttons.firstWhere((b) => b.label == buttonLabel);
  }

  Future<void> pressAndAssert(EmulatedButton button, ControllerButton expected) async {
    button.onDown();
    button.onUp();
    await IntegrationEnv.waitFor(() => stubActions.performedActions.isNotEmpty, description: 'performed action');
    expect(stubActions.performedActions.map((a) => a.button), contains(expected));
  }

  test('Zwift Play left: Nav Up press performs navigationUp', () async {
    final button = await connectAndFirstButton<ZwiftPlay>(
      zwiftPlayLeftProfile,
      'emulated:zwift-play-left',
      buttonLabel: 'Nav Up',
    );
    await pressAndAssert(button, ZwiftButtons.navigationUp);
  });

  test('Zwift Play right: Y press performs y', () async {
    final button = await connectAndFirstButton<ZwiftPlay>(
      zwiftPlayRightProfile,
      'emulated:zwift-play-right',
      buttonLabel: 'Y',
    );
    await pressAndAssert(button, ZwiftButtons.y);
  });

  test('Zwift Play FW2: SHFT_UP_R press performs shiftUpRight', () async {
    final button = await connectAndFirstButton<ZwiftPlayFw2>(
      zwiftPlayFw2Profile,
      'emulated:zwift-play-fw2',
      buttonLabel: 'SHFT_UP_R_BTN',
    );
    await pressAndAssert(button, ZwiftButtons.shiftUpRight);
  });

  test('Zwift Click V2 left side: UP press performs navigationUp', () async {
    final button = await connectAndFirstButton<ZwiftClickV2LeftSide>(
      zwiftClickV2LeftProfile,
      'emulated:zwift-clickv2-left',
      buttonLabel: 'UP_BTN',
    );
    await pressAndAssert(button, ZwiftButtons.navigationUp);
  });

  test('Zwift Click V2 right side: A press performs a', () async {
    final button = await connectAndFirstButton<ZwiftClickV2RightSide>(
      zwiftClickV2RightProfile,
      'emulated:zwift-clickv2-right',
      buttonLabel: 'A_BTN',
    );
    await pressAndAssert(button, ZwiftButtons.a);
  });
}
