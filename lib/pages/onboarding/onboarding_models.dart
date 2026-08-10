enum OnboardingStep { app, where, controller, virtualShifting, connection, done }

/// Sub-phases of the controller step. "Connected" is not a phase — it is
/// derived live from `core.connection.controllerDevices` so auto-connect can
/// flip the UI at any moment.
enum ControllerPhase { permission, scanning, empty, list }

/// BikeControl-as-trainer-app is self-hosted, so "where does it run" is
/// meaningless — the settings side of this rule lives in
/// applyTrainerAppSelection (Task 4), which pins Target.thisDevice.
OnboardingStep onboardingNextStep(OnboardingStep step, {required bool appIsSelfHosted}) {
  if (step == OnboardingStep.done) return OnboardingStep.done;
  var next = OnboardingStep.values[step.index + 1];
  if (next == OnboardingStep.where && appIsSelfHosted) {
    next = OnboardingStep.controller;
  }
  return next;
}

OnboardingStep onboardingPreviousStep(OnboardingStep step, {required bool appIsSelfHosted}) {
  if (step == OnboardingStep.app) return OnboardingStep.app;
  var prev = OnboardingStep.values[step.index - 1];
  if (prev == OnboardingStep.where && appIsSelfHosted) {
    prev = OnboardingStep.app;
  }
  return prev;
}