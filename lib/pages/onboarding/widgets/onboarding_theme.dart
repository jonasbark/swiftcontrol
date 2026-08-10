import 'package:bike_control/widgets/ui/colors.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

/// The wizard's accent. `colorScheme.primary` is only overridden to the brand
/// blue in the LIGHT theme — in dark it stays the slate scheme's near-white,
/// which made white-on-accent icons and check marks invisible. These helpers
/// keep the design's brand accent in both themes, with a lightened tone in
/// dark so it stays legible on the dark card.
Color onboardingAccent(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark ? const Color(0xFF4DA9E8) : BKColor.main;

/// Content drawn on top of [onboardingAccent] — white in both themes.
const Color onboardingOnAccent = Color(0xFFFFFFFF);
