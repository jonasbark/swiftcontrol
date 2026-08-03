import 'package:bike_control/gen/l10n.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('onboarding strings resolve in every shipped language', () async {
    for (final code in ['en', 'de', 'es', 'fr', 'it', 'pl']) {
      final l10n = await AppLocalizations.load(Locale(code));
      final strings = [
        l10n.clickV2Onboarding_cardTitle,
        l10n.clickV2Onboarding_cardSubtitle,
        l10n.clickV2Onboarding_title,
        l10n.clickV2Onboarding_intro,
        l10n.clickV2Onboarding_whyLink,
        l10n.clickV2Onboarding_leftOnlyTitle,
        l10n.clickV2Onboarding_leftOnlyPro1,
        l10n.clickV2Onboarding_leftOnlyPro2,
        l10n.clickV2Onboarding_leftOnlyCon1,
        l10n.clickV2Onboarding_leftOnlyCon2,
        l10n.clickV2Onboarding_leftOnlyCta,
        l10n.clickV2Onboarding_zwiftTitle,
        l10n.clickV2Onboarding_zwiftPro1,
        l10n.clickV2Onboarding_zwiftPro2,
        l10n.clickV2Onboarding_zwiftCon1,
        l10n.clickV2Onboarding_zwiftCon2,
        l10n.clickV2Onboarding_zwiftCta,
        l10n.clickV2Onboarding_alternativesLink,
        l10n.clickV2Onboarding_setUpAgain,
      ];
      for (final value in strings) {
        expect(value, isNotEmpty, reason: 'empty string for locale $code');
      }
    }
  });
}
