import 'package:bike_control/main.dart' show screenshotMode;
import 'package:bike_control/pages/onboarding/widgets/onboarding_theme.dart';
import 'package:bike_control/utils/i18n_extension.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

/// Reveals its child with a fade + rise once [delay] has elapsed. Static under
/// reduced motion and in screenshotMode so captures stay deterministic.
class _Reveal extends StatelessWidget {
  const _Reveal({required this.child, required this.delay});
  final Widget child;
  final Duration delay;

  @override
  Widget build(BuildContext context) {
    if (screenshotMode || MediaQuery.of(context).disableAnimations) return child;
    const span = Duration(milliseconds: 520);
    final total = span + delay;
    final start = delay.inMilliseconds / total.inMilliseconds;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: total,
      curve: Interval(start, 1, curve: Curves.easeOutCubic),
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(offset: Offset(0, 14 * (1 - t)), child: child),
      ),
      child: child,
    );
  }
}

/// The mobile-only welcome screen: the headline's words arrive one after the
/// other, then the subtitle, the reassurance rows and the actions.
///
/// [onStart] enters the wizard; [onLater] leaves it — and marks onboarding
/// done, so riders who decline aren't asked again on every launch.
class OnboardingWelcome extends StatelessWidget {
  const OnboardingWelcome({super.key, required this.onStart, required this.onLater});
  final VoidCallback onStart;
  final VoidCallback onLater;

  @override
  Widget build(BuildContext context) {
    final accent = onboardingAccent(context);
    final words = context.i18n.onboardingWelcomeTitle.split(' ');

    Widget point(IconData icon, String text, int index) => _Reveal(
          delay: Duration(milliseconds: 900 + index * 110),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(children: [
              Container(
                width: 30,
                height: 30,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: accent.withValues(alpha: 0.12),
                ),
                child: Icon(icon, size: 15, color: accent),
              ),
              Gap(12),
              Expanded(child: Text(text).small),
            ]),
          ),
        );

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Spacer(flex: 2),
            _Reveal(
              delay: Duration.zero,
              child: Image.asset('icon.png', width: 64, height: 64),
            ),
            Gap(22),
            // Word-by-word reveal — the headline writes itself in.
            Wrap(
              spacing: 9,
              runSpacing: 2,
              children: [
                for (var i = 0; i < words.length; i++)
                  _Reveal(
                    delay: Duration(milliseconds: 180 + i * 90),
                    child: Text(words[i]).x3Large.semiBold,
                  ),
              ],
            ),
            Gap(12),
            _Reveal(
              delay: Duration(milliseconds: 180 + words.length * 90),
              child: Text(context.i18n.onboardingWelcomeSubtitle).small.muted,
            ),
            Gap(26),
            point(LucideIcons.gamepad2, context.i18n.onboardingWelcomePointController, 0),
            point(LucideIcons.bike, context.i18n.onboardingWelcomePointTrainer, 1),
            point(LucideIcons.wifi, context.i18n.onboardingWelcomePointApp, 2),
            const Spacer(flex: 3),
            _Reveal(
              delay: const Duration(milliseconds: 1300),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                PrimaryButton(
                  onPressed: onStart,
                  child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Text(context.i18n.onboardingWelcomeStart),
                    Gap(8),
                    Icon(LucideIcons.arrowRight, size: 16),
                  ]),
                ),
                Gap(8),
                GhostButton(onPressed: onLater, child: Center(child: Text(context.i18n.onboardingWelcomeLater))),
                Gap(6),
                Center(child: Text(context.i18n.onboardingWelcomeFootnote).xSmall.muted),
              ]),
            ),
          ],
        ),
      ),
    );
  }
}
