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
    test('defers while the wizard is about to take the screen', () {
      // Checking a permission means asking for it on Apple platforms; a dialog
      // arriving from behind the wizard explains nothing.
      expect(
        deferLaunchPermissionChecks(onboardingAction: OnboardingTriggerAction.show),
        isTrue,
      );
    });

    test('checks once onboarding is settled', () {
      // A rider who revoked a permission in System Settings should find out at
      // launch, not from a connection that silently does nothing.
      for (final action in [OnboardingTriggerAction.none, OnboardingTriggerAction.markCompleted]) {
        expect(
          deferLaunchPermissionChecks(onboardingAction: action),
          isFalse,
          reason: '$action must still check',
        );
      }
    });
  });
}
