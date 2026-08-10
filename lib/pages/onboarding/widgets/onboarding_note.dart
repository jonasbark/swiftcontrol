import 'package:bike_control/pages/onboarding/widgets/onboarding_theme.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

/// The design's info strip: icon + text on a brand-tinted wash.
class OnboardingNote extends StatelessWidget {
  const OnboardingNote(this.text, {super.key, this.icon = LucideIcons.info});
  final String text;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        color: onboardingAccent(context).withValues(alpha: 0.07),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 15, color: onboardingAccent(context)),
        Gap(9),
        Expanded(child: Text(text).xSmall),
      ]),
    );
  }
}
