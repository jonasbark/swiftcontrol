import 'package:bike_control/pages/onboarding/onboarding_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('next advances linearly', () {
    expect(onboardingNextStep(OnboardingStep.app, appIsSelfHosted: false), OnboardingStep.where);
    expect(onboardingNextStep(OnboardingStep.connection, appIsSelfHosted: false), OnboardingStep.done);
  });

  test('self-hosted app (BikeControl) skips the where step in both directions', () {
    expect(onboardingNextStep(OnboardingStep.app, appIsSelfHosted: true), OnboardingStep.controller);
    expect(onboardingPreviousStep(OnboardingStep.controller, appIsSelfHosted: true), OnboardingStep.app);
  });

  test('done does not advance, app does not go back', () {
    expect(onboardingNextStep(OnboardingStep.done, appIsSelfHosted: false), OnboardingStep.done);
    expect(onboardingPreviousStep(OnboardingStep.app, appIsSelfHosted: false), OnboardingStep.app);
  });

  group('shouldAdvanceOnButtonPress', () {
    test('wrong step -> false', () {
      expect(
        shouldAdvanceOnButtonPress(
          step: OnboardingStep.virtualShifting,
          phase: ControllerPhase.list,
          subFlowOpen: false,
          anyControllerConnected: true,
        ),
        false,
      );
    });

    test('controller + list + connected + no subflow -> true', () {
      expect(
        shouldAdvanceOnButtonPress(
          step: OnboardingStep.controller,
          phase: ControllerPhase.list,
          subFlowOpen: false,
          anyControllerConnected: true,
        ),
        true,
      );
    });

    test('subflow open -> false', () {
      expect(
        shouldAdvanceOnButtonPress(
          step: OnboardingStep.controller,
          phase: ControllerPhase.list,
          subFlowOpen: true,
          anyControllerConnected: true,
        ),
        false,
      );
    });

    test('phase != list -> false', () {
      expect(
        shouldAdvanceOnButtonPress(
          step: OnboardingStep.controller,
          phase: ControllerPhase.scanning,
          subFlowOpen: false,
          anyControllerConnected: true,
        ),
        false,
      );
    });

    test('not connected -> false', () {
      expect(
        shouldAdvanceOnButtonPress(
          step: OnboardingStep.controller,
          phase: ControllerPhase.list,
          subFlowOpen: false,
          anyControllerConnected: false,
        ),
        false,
      );
    });
  });
}
