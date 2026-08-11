// The paywall used NumberFormat.currency(name:), which prints the ISO code
// ("EUR 2,08") instead of the symbol riders expect.
import 'package:bike_control/pages/paywall.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('uses the symbol from the store price, not the ISO code', () {
    final euro = paywallFormatPrice(2.0825, 'EUR', sampleFormattedPrice: '24,99 €');
    expect(euro, contains('€'));
    expect(euro, isNot(contains('EUR')));

    final dollar = paywallFormatPrice(2.4158, 'USD', sampleFormattedPrice: r'$28.99');
    expect(dollar, contains(r'$'));
    expect(dollar, isNot(contains('USD')));
  });

  test('falls back to a symbol when the store gave us no sample', () {
    final euro = paywallFormatPrice(2.08, 'EUR');
    expect(euro, isNot(contains('EUR')), reason: 'simpleCurrency resolves EUR to €');
  });

  test('rounds to two decimals', () {
    expect(paywallFormatPrice(2.0825, 'EUR', sampleFormattedPrice: '24,99 €'), contains('2.08'));
  });
}
