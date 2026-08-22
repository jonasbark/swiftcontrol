import 'package:bike_control/utils/analytics/campaign_attributes.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('campaignAttributes', () {
    test('maps the four UTMs onto RevenueCat reserved keys', () {
      final result = campaignAttributes(
        'utm_source=facebook&utm_medium=paid&utm_campaign=di2-launch-2026-08&utm_content=AD-DI2-EN-FEATURE',
      );

      expect(result, {
        r'$campaign': 'di2-launch-2026-08',
        r'$mediaSource': 'facebook',
        r'$adGroup': 'AD-DI2-EN-FEATURE',
        r'$ad': 'AD-DI2-EN-FEATURE',
        'bikecontrol_utm_medium': 'paid',
      });
    });

    test('carries the organic install through so paid can be compared to it', () {
      expect(campaignAttributes('utm_source=google-play&utm_medium=organic'), {
        r'$mediaSource': 'google-play',
        'bikecontrol_utm_medium': 'organic',
      });
    });

    test('returns empty when there is no referrer or no UTMs in it', () {
      expect(campaignAttributes(null), isEmpty);
      expect(campaignAttributes(''), isEmpty);
      expect(campaignAttributes('not_a_utm=1'), isEmpty);
    });

    test('emits only the keys the referrer actually carries', () {
      expect(campaignAttributes('utm_campaign=di2-launch-2026-08'), {
        r'$campaign': 'di2-launch-2026-08',
      });
    });

    test('lets a malformed referrer throw so the caller can record it', () {
      // Same contract as parseInstallReferrer: a bad percent escape surfaces as
      // ArgumentError rather than being silently turned into "no campaign".
      // setAttributes catches it and routes it through recordError.
      expect(() => campaignAttributes('utm_source=%zz'), throwsArgumentError);
    });
  });
}
