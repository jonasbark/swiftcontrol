import 'package:bike_control/utils/actions/base_actions.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BaseActions.isExemptInternalTrainerAction', () {
    // Free tester changing gears on a live bridge a trainer app is holding.
    bool exempt({
      bool handledInternally = true,
      bool isProForDevice = false,
      bool hasFullVersion = false,
      bool bridgeCountingDown = true,
      bool appHoldsBridge = true,
    }) =>
        BaseActions.isExemptInternalTrainerAction(
          handledInternally: handledInternally,
          isProForDevice: isProForDevice,
          hasFullVersion: hasFullVersion,
          bridgeCountingDown: bridgeCountingDown,
          appHoldsBridge: appHoldsBridge,
        );

    test('exempt when a free tester changes gears internally on a live bridge', () {
      expect(exempt(), isTrue);
    });

    test('not exempt when the action was not handled internally by the FBD', () {
      expect(exempt(handledInternally: false), isFalse);
    });

    test('not exempt for a Pro (this device) user', () {
      expect(exempt(isProForDevice: true), isFalse);
    });

    test('not exempt for a full-version owner', () {
      expect(exempt(hasFullVersion: true), isFalse);
    });

    test('not exempt once the 20-minute bridge budget is no longer counting down', () {
      expect(exempt(bridgeCountingDown: false), isFalse);
    });

    // A shift with no trainer app holding the bridge reaches nothing, so there
    // is no delivered command to charge for.
    test('exempt when no trainer app has picked the bridge up', () {
      expect(exempt(bridgeCountingDown: false, appHoldsBridge: false), isTrue);
    });

    test('still exempt when the budget ticks and the app has not picked it up', () {
      expect(exempt(appHoldsBridge: false), isTrue);
    });

    test('an undelivered shift is still not exempt for owners', () {
      expect(exempt(bridgeCountingDown: false, appHoldsBridge: false, hasFullVersion: true), isFalse);
      expect(exempt(bridgeCountingDown: false, appHoldsBridge: false, isProForDevice: true), isFalse);
    });

    test('an undelivered action the trainer did not handle is still counted', () {
      expect(exempt(handledInternally: false, appHoldsBridge: false), isFalse);
    });
  });
}
