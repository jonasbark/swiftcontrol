import 'package:bike_control/pages/onboarding/onboarding_trigger.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('fresh install, never triggered -> show', () {
    expect(
      decideOnboardingTrigger(lastSeenVersion: null, onboardingState: null),
      OnboardingTriggerAction.show,
    );
  });

  test('existing install, never triggered -> silently mark completed', () {
    expect(
      decideOnboardingTrigger(lastSeenVersion: '6.2.0', onboardingState: null),
      OnboardingTriggerAction.markCompleted,
    );
  });

  test('pending (quit mid-flow) -> show again, even though a version is now recorded', () {
    expect(
      decideOnboardingTrigger(lastSeenVersion: '6.3.0', onboardingState: 'pending'),
      OnboardingTriggerAction.show,
    );
  });

  test('completed -> none', () {
    expect(
      decideOnboardingTrigger(lastSeenVersion: '6.3.0', onboardingState: 'completed'),
      OnboardingTriggerAction.none,
    );
  });

  group('deferLaunchPermissionChecks', () {
    test('defers on a fresh install with nothing switched on', () {
      // Nothing is configured and the wizard has not run, so a launch-time
      // permission dialog would arrive with no context to explain it.
      expect(
        deferLaunchPermissionChecks(
          onboardingAction: OnboardingTriggerAction.show,
          anyConnectionMethodEnabled: false,
        ),
        isTrue,
      );
    });

    test('still checks when the rider already enabled a connection method', () {
      // They opted into something that needs permissions — asking is in context
      // even though the wizard has not finished.
      expect(
        deferLaunchPermissionChecks(
          onboardingAction: OnboardingTriggerAction.show,
          anyConnectionMethodEnabled: true,
        ),
        isFalse,
      );
    });

    test('never defers once onboarding is settled', () {
      for (final action in [OnboardingTriggerAction.none, OnboardingTriggerAction.markCompleted]) {
        for (final enabled in [true, false]) {
          expect(
            deferLaunchPermissionChecks(onboardingAction: action, anyConnectionMethodEnabled: enabled),
            isFalse,
            reason: '$action with anyConnectionMethodEnabled=$enabled must still check',
          );
        }
      }
    });
  });
}
