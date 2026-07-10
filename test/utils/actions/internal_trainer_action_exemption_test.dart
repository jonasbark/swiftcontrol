import 'package:bike_control/utils/actions/base_actions.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BaseActions.isExemptInternalTrainerAction', () {
    // Free tester changing gears on a live bridge: every condition met.
    bool exempt({
      bool handledInternally = true,
      bool isProForDevice = false,
      bool hasFullVersion = false,
      bool bridgeCountingDown = true,
    }) =>
        BaseActions.isExemptInternalTrainerAction(
          handledInternally: handledInternally,
          isProForDevice: isProForDevice,
          hasFullVersion: hasFullVersion,
          bridgeCountingDown: bridgeCountingDown,
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
  });
}
