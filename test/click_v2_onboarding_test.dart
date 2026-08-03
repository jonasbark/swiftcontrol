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
}
