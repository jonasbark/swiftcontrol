// Widget test for the in-app language switcher (LanguageSelect). Opens the
// Select and picks a non-system locale, asserting the override is persisted.
import 'package:bike_control/gen/l10n.dart';
import 'package:bike_control/main.dart' show OtherLocalizationsDelegate;
import 'package:bike_control/pages/trainer_connection_settings.dart';
import 'package:bike_control/utils/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    core.settings.prefs = await SharedPreferences.getInstance();
  });

  Widget harness() => ShadcnApp(
        debugShowCheckedModeBanner: false,
        localizationsDelegates: [
          ...ShadcnLocalizations.localizationsDelegates,
          const OtherLocalizationsDelegate(),
          AppLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.delegate.supportedLocales,
        theme: ThemeData(colorScheme: ColorSchemes.lightSlate, radius: 0.7),
        home: Scaffold(
          child: LanguageSelect(onChanged: () {}),
        ),
      );

  testWidgets('choosing a language persists the override', (tester) async {
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    // Starts on system default (no override).
    expect(core.settings.getLocaleOverride(), isNull);

    // Open the language Select popup.
    await tester.tap(find.byType(Select<String>));
    await tester.pumpAndSettle();

    // Pick German by its native name (endonym).
    await tester.tap(find.text('Deutsch').last);
    await tester.pumpAndSettle();

    expect(core.settings.getLocaleOverride(), 'de');
    expect(core.settings.localeListenable.value, const Locale('de'));
  });
}
