import 'package:bike_control/main.dart';
import 'package:bike_control/utils/core.dart';

/// Policy for the one-time Zwift Click V2 unlock-mode onboarding.
///
/// Zwift locks the Click V2 to their own app. BikeControl implements two
/// workarounds, and which one suits a rider is a real trade-off — so a newly
/// discovered Click V2 is held out of the connect queue until the rider has
/// seen the explainer and picked one.
///
/// Every consumer (the device classes' connect gate, the placeholder card and
/// the onboarding page) reads this class rather than assembling its own
/// settings checks, so the rule lives in exactly one place.
abstract final class ClickV2Onboarding {
  /// Whether a discovered Click V2 should be held back for onboarding.
  static bool get isPending {
    // Screenshot frames connect fake controllers directly and must never be
    // interrupted by an onboarding card.
    if (screenshotMode) return false;
    if (!core.settings.isInitialized) return false;
    if (core.settings.getClickV2OnboardingDone()) return false;
    // `unlock_mode` defaults to false, so a true value can only come from a
    // deliberate past choice. Those riders are already settled — don't
    // re-onboard them.
    if (core.settings.getUnlockWithZwift()) return false;
    return true;
  }
}
