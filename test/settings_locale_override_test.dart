import 'package:bike_control/utils/settings/settings.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('locale override defaults to null (system)', () async {
    final s = Settings();
    s.prefs = await SharedPreferences.getInstance();
    expect(s.getLocaleOverride(), isNull);
    expect(s.localeListenable.value, isNull);
  });

  test('setting an override persists code and updates the listenable', () async {
    final s = Settings();
    s.prefs = await SharedPreferences.getInstance();

    await s.setLocaleOverride('de');
    expect(s.getLocaleOverride(), 'de');
    expect(s.localeListenable.value, const Locale('de'));
  });

  test('clearing the override removes the key and clears the listenable', () async {
    final s = Settings();
    s.prefs = await SharedPreferences.getInstance();

    await s.setLocaleOverride('de');
    expect(s.getLocaleOverride(), 'de');

    await s.setLocaleOverride(null);
    expect(s.getLocaleOverride(), isNull);
    expect(s.localeListenable.value, isNull);
    expect(s.prefs.containsKey('locale_override'), isFalse);
  });
}
