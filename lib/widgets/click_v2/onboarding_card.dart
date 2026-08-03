import 'package:bike_control/pages/click_v2_onboarding.dart';
import 'package:bike_control/utils/i18n_extension.dart';
import 'package:bike_control/widgets/click_v2/click_contours.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

/// Placeholder for a discovered-but-not-yet-connected Zwift Click V2.
///
/// The header is faded to signal "not live yet"; the call to action keeps full
/// strength so it does not read as a disabled card. One card stands in for the
/// whole controller, however many of its two sides are in range — the unlock
/// mode is a single decision about a single device.
class ClickV2OnboardingCard extends StatelessWidget {
  const ClickV2OnboardingCard({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.i18n;
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 12,
        children: [
          Opacity(
            key: const ValueKey('click-onboarding-card-header'),
            opacity: 0.45,
            child: Row(
              spacing: 12,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const SizedBox(width: 64, height: 40, child: ClickContours(page: 1)),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: 4,
                    children: [
                      const Text('Zwift Click V2').semiBold,
                      Text(l10n.clickV2Onboarding_cardSubtitle).xSmall.muted,
                    ],
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            width: double.infinity,
            child: Button.primary(
              trailing: const Icon(Icons.arrow_forward, size: 16),
              onPressed: () => context.push(const ClickV2OnboardingPage()),
              child: Text(l10n.clickV2Onboarding_cardTitle),
            ),
          ),
        ],
      ),
    );
  }
}
