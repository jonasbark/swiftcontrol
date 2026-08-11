import 'package:bike_control/bluetooth/devices/zwift/constants.dart';
import 'package:bike_control/bluetooth/devices/zwift/zwift_clickv2_left_side.dart';
import 'package:bike_control/bluetooth/devices/zwift/zwift_clickv2_right_side.dart';
import 'package:bike_control/main.dart';
import 'package:bike_control/utils/actions/base_actions.dart';
import 'package:bike_control/utils/click_v2_onboarding.dart';
import 'package:bike_control/utils/core.dart';
import 'package:bike_control/utils/keymap/apps/custom_app.dart';
import 'package:bike_control/utils/keymap/apps/zwift.dart';
import 'package:bike_control/utils/keymap/buttons.dart';
import 'package:bike_control/utils/keymap/keymap.dart';
import 'package:bike_control/utils/settings/settings.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:universal_ble/universal_ble.dart';

ZwiftClickV2LeftSide _leftSide() => ZwiftClickV2LeftSide(
  BleDevice(deviceId: 'left-1', name: 'Zwift Click', manufacturerDataList: const [], services: const []),
);

ZwiftClickV2RightSide _rightSide() => ZwiftClickV2RightSide(
  BleDevice(deviceId: 'right-1', name: 'Zwift Click', manufacturerDataList: const [], services: const []),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Click V2 onboarding setting', () {
    late Settings settings;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      settings = Settings();
      settings.prefs = await SharedPreferences.getInstance();
    });

    test('defaults to not done', () {
      expect(settings.getClickV2OnboardingDone(), isFalse);
    });

    test('round-trips', () async {
      await settings.setClickV2OnboardingDone(true);
      expect(settings.getClickV2OnboardingDone(), isTrue);

      await settings.setClickV2OnboardingDone(false);
      expect(settings.getClickV2OnboardingDone(), isFalse);
    });

    test('reports done when prefs were never initialised', () {
      // Device detection can run before Settings.init (e.g. in unit tests).
      // Reporting "done" keeps an uninitialised Settings from ever gating a
      // connection, and must not throw on the late `prefs` field.
      expect(Settings().getClickV2OnboardingDone(), isTrue);
    });

    test('exposes whether prefs are initialised', () {
      expect(settings.isInitialized, isTrue);
      expect(Settings().isInitialized, isFalse);
    });
  });

  group('ClickV2Onboarding.isPending', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      core.settings.prefs = await SharedPreferences.getInstance();
      screenshotMode = false;
    });

    tearDown(() {
      screenshotMode = false;
    });

    test('pending for a fresh install', () {
      expect(ClickV2Onboarding.isPending, isTrue);
    });

    test('not pending once completed', () async {
      await core.settings.setClickV2OnboardingDone(true);
      expect(ClickV2Onboarding.isPending, isFalse);
    });

    test('not pending for riders who already chose unlock-with-Zwift', () async {
      // unlock_mode defaults to false, so true can only be a deliberate past
      // choice — those riders are treated as already onboarded.
      await core.settings.setUnlockWithZwift(true);
      expect(ClickV2Onboarding.isPending, isFalse);
    });

    test('still pending for riders on the default restart mode', () async {
      await core.settings.setUnlockWithZwift(false);
      expect(ClickV2Onboarding.isPending, isTrue);
    });

    test('never pending in screenshot mode', () {
      screenshotMode = true;
      expect(ClickV2Onboarding.isPending, isFalse);
    });
  });

  group('right-side-only setting', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      core.settings.prefs = await SharedPreferences.getInstance();
    });

    test('defaults to off and round-trips', () async {
      expect(core.settings.getClickV2RightSideOnly(), isFalse);

      await core.settings.setClickV2RightSideOnly(true);
      expect(core.settings.getClickV2RightSideOnly(), isTrue);

      await core.settings.setClickV2RightSideOnly(false);
      expect(core.settings.getClickV2RightSideOnly(), isFalse);
    });

    test('reads false when prefs were never initialised', () {
      // Both connect gates read this during device detection, which can run
      // before Settings.init. It must not throw on the late `prefs` field, and
      // "off" is the answer that changes no existing behaviour.
      expect(Settings().getClickV2RightSideOnly(), isFalse);
    });
  });

  // The three modes differ only in which pucks are allowed to connect, so the
  // gates are the mode. ClickLogic drives the left side's restart loop from a
  // single shared timer that the right side's handshake cancels — hence the
  // rule that those two are never live together.
  group('connect gates per unlock mode', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      core.settings.prefs = await SharedPreferences.getInstance();
      await core.settings.setClickV2OnboardingDone(true);
      screenshotMode = false;
    });

    test('right-side-only: right connects, left is held back', () async {
      await core.settings.setClickV2RightSideOnly(true);
      await core.settings.setUnlockWithZwift(false);

      expect(_rightSide().shouldAutoConnect, isTrue);
      expect(_leftSide().shouldAutoConnect, isFalse);
    });

    test('unlock-with-Zwift: both sides connect', () async {
      await core.settings.setClickV2RightSideOnly(false);
      await core.settings.setUnlockWithZwift(true);

      expect(_rightSide().shouldAutoConnect, isTrue);
      expect(_leftSide().shouldAutoConnect, isTrue);
    });

    test('legacy left-side restart mode: left connects, right is held back', () async {
      await core.settings.setClickV2RightSideOnly(false);
      await core.settings.setUnlockWithZwift(false);

      expect(_rightSide().shouldAutoConnect, isFalse);
      expect(_leftSide().shouldAutoConnect, isTrue);
    });

    test('nothing connects while the mode is still unchosen', () async {
      await core.settings.setClickV2OnboardingDone(false);

      expect(ClickV2Onboarding.isPending, isTrue);
      expect(_rightSide().shouldAutoConnect, isFalse);
      expect(_leftSide().shouldAutoConnect, isFalse);
    });
  });

  group('chooseRightSideOnly keymap', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      core.settings.prefs = await SharedPreferences.getInstance();
      core.actionHandler = StubActions();
    });

    // One puck has to cover both directions. Zwift's built-in map binds the
    // right paddle to shiftUp and the *left* paddle to shiftDown, so without
    // this remap the rider could only ever shift up.
    test('leaves the right puck able to shift both ways', () async {
      core.actionHandler.supportedApp = Zwift();

      await ClickV2Onboarding.chooseRightSideOnly();

      final app = core.actionHandler.supportedApp;
      expect(app, isA<CustomApp>());
      expect(app!.keymap.getKeyPair(ZwiftButtons.shiftUpRight, trigger: ButtonTrigger.singleClick)?.inGameAction,
          InGameAction.shiftUp);
      expect(app.keymap.getKeyPair(ZwiftButtons.b, trigger: ButtonTrigger.singleClick)?.inGameAction,
          InGameAction.shiftDown);
    });

    // The remap is a convenience layered on the mode; the mode is the thing
    // the rider actually chose. A keymap that can't be written (no trainer app
    // picked yet) must not leave the choice half-applied.
    test('still applies the mode when no trainer app is selected', () async {
      core.actionHandler.supportedApp = null;

      await ClickV2Onboarding.chooseRightSideOnly();

      expect(core.settings.getClickV2RightSideOnly(), isTrue);
      expect(core.settings.getUnlockWithZwift(), isFalse);
      expect(core.settings.getClickV2OnboardingDone(), isTrue);
    });
  });
}
