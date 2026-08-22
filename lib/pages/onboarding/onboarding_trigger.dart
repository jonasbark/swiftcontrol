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

/// Whether work triggered by app launch should be skipped entirely.
///
/// Permissions *are* checked at launch — a rider who revoked one in System
/// Settings should find out then, not from a silently dead connection. The
/// exception is while the first-run wizard is about to take over the screen:
/// checking a permission means *asking* for it on Apple platforms, and a
/// dialog or a warning toast arriving from behind the wizard explains nothing.
/// Onboarding asks for what it needs, when it needs it.
bool deferLaunchPermissionChecks({required OnboardingTriggerAction onboardingAction}) =>
    onboardingAction == OnboardingTriggerAction.show;
