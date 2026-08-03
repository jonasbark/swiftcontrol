import 'package:bike_control/main.dart';
import 'package:bike_control/utils/click_v2_onboarding.dart';
import 'package:bike_control/utils/core.dart';
import 'package:bike_control/utils/settings/settings.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
}
