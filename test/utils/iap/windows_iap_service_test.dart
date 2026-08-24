import 'package:bike_control/utils/iap/windows_iap_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Regression: on the Windows Stripe build the paywall's "Login Required" gate
  // was a dead end — the rider authenticated (email code or the external-browser
  // OAuth redirect) and the Stripe checkout never started. We now stash the
  // checkout the rider asked for and resume it once `signedIn` fires.
  // [checkoutToResume] is the pure decision behind that resume.
  group('WindowsIAPService.checkoutToResume', () {
    test('nothing pending never checks out', () {
      expect(
        WindowsIAPService.checkoutToResume(pending: null, isLoggedIn: true, isAlreadyPro: false),
        isNull,
      );
    });

    test('resumes the exact plan the rider started before logging in', () {
      for (final priceId in ['monthly', 'yearly', 'full']) {
        expect(
          WindowsIAPService.checkoutToResume(pending: priceId, isLoggedIn: true, isAlreadyPro: false),
          priceId,
        );
      }
    });

    test('a signed-in event without a live session does not check out', () {
      // e.g. a token refresh / sign-out race — never launch Stripe without auth.
      expect(
        WindowsIAPService.checkoutToResume(pending: 'yearly', isLoggedIn: false, isAlreadyPro: false),
        isNull,
      );
    });

    test('an already-Pro account is not charged again', () {
      // Logging into an account that is already entitled must not open checkout.
      expect(
        WindowsIAPService.checkoutToResume(pending: 'full', isLoggedIn: true, isAlreadyPro: true),
        isNull,
      );
    });
  });
}
