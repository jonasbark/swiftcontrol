import 'package:bike_control/utils/analytics/install_referrer_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseInstallReferrer', () {
    test('extracts the four UTM keys from a Play referrer', () {
      final result = parseInstallReferrer(
        'utm_source=facebook&utm_medium=paid&utm_campaign=di2-launch-2026-08&utm_content=AD-DI2-EN-FEATURE',
      );

      expect(result, {
        'utm_source': 'facebook',
        'utm_medium': 'paid',
        'utm_campaign': 'di2-launch-2026-08',
        'utm_content': 'AD-DI2-EN-FEATURE',
      });
    });

    test('returns empty for null, blank or UTM-less referrers', () {
      expect(parseInstallReferrer(null), isEmpty);
      expect(parseInstallReferrer(''), isEmpty);
      expect(parseInstallReferrer('   '), isEmpty);
      // Play's own organic value carries no utm_content/campaign we care about.
      expect(parseInstallReferrer('not_a_utm=1&other=2'), isEmpty);
    });

    test('keeps Play organic referrers that do use utm keys', () {
      expect(parseInstallReferrer('utm_source=google-play&utm_medium=organic'), {
        'utm_source': 'google-play',
        'utm_medium': 'organic',
      });
    });

    test('decodes percent-encoded values', () {
      expect(parseInstallReferrer('utm_content=a%26b'), {'utm_content': 'a&b'});
    });

    test('ignores unknown keys and empty values', () {
      expect(parseInstallReferrer('utm_source=facebook&gclid=xyz&utm_medium='), {
        'utm_source': 'facebook',
      });
    });

    test('trims whitespace and caps values at 200 characters', () {
      expect(parseInstallReferrer('utm_source=%20facebook%20'), {'utm_source': 'facebook'});

      final long = 'x' * 250;
      final result = parseInstallReferrer('utm_campaign=$long');
      expect(result['utm_campaign']!.length, 200);
    });

    test('throws FormatException on malformed percent-encoding', () {
      expect(() => parseInstallReferrer('utm_source=100%'), throwsFormatException);
    });
  });
}
