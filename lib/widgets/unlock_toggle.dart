import 'package:bike_control/pages/click_v2_onboarding.dart';
import 'package:bike_control/utils/core.dart';
import 'package:bike_control/utils/i18n_extension.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:url_launcher/url_launcher_string.dart';

/// The unlock-mode header shown on both Zwift Click V2 pucks: what the mode is
/// called, where to read about it, and the way back into the explainer that
/// sets it.
///
/// Deliberately not a mode picker. The explainer is the one place the choice is
/// made — it is what applies the follow-on work each mode needs (un-ignoring
/// the left puck, remapping for right-side-only, cancelling the reset timer),
/// none of which a bare dropdown did.
class UnlockToggle extends StatefulWidget {
  /// Shown only in unlock-with-Zwift mode — the warnings that mode implies.
  final List<Widget> children;
  const UnlockToggle({super.key, required this.children});

  @override
  State<UnlockToggle> createState() => _UnlockToggleState();
}

class _UnlockToggleState extends State<UnlockToggle> {
  bool _unlockWithZwift = false;

  @override
  void initState() {
    _unlockWithZwift = core.settings.getUnlockWithZwift();
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 8,
      children: [
        Row(
          children: [
            Text(context.i18n.unlock_mode).small.semiBold,
            IconButton.link(
              icon: Icon(Icons.help_outline),
              onPressed: () {
                launchUrlString('https://bikecontrol.app/blog/zwift-click-v2-with-other-trainer-apps');
              },
            ),
            const Spacer(),
            // The explainer that introduced these two modes stays reachable
            // after onboarding, so the trade-offs can be re-read later.
            Button.ghost(
              onPressed: () async {
                await context.push(const ClickV2OnboardingPage());
                if (!mounted) return;
                // The page writes the setting directly, so re-read it: the
                // gated warning children below have to follow the new choice.
                setState(() => _unlockWithZwift = core.settings.getUnlockWithZwift());
              },
              child: Text(context.i18n.clickV2Onboarding_setUpAgain).xSmall,
            ),
          ],
        ),

        if (_unlockWithZwift) ...widget.children,
      ],
    );
  }
}
