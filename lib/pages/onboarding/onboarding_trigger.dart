enum OnboardingTriggerAction { show, markCompleted, none }

/// Pure decision, unit-testable without SharedPreferences.
///
/// [onboardingState] is the raw `onboarding_state` pref: null (never
/// triggered), 'pending' (started, not finished) or 'completed'.
/// [lastSeenVersion] is null exactly on a fresh install — the changelog
/// mechanism ([Settings.setLastSeenVersion]) writes it on every launch.
/// The 'pending' check must come before the fresh-install check: after the
/// first launch a version is recorded, but a rider who quit mid-flow still
/// gets the wizard back.
OnboardingTriggerAction decideOnboardingTrigger({
  required String? lastSeenVersion,
  required String? onboardingState,
}) {
  if (onboardingState == 'completed') return OnboardingTriggerAction.none;
  if (onboardingState == 'pending') return OnboardingTriggerAction.show;
  return lastSeenVersion == null
      ? OnboardingTriggerAction.show
      : OnboardingTriggerAction.markCompleted;
}
