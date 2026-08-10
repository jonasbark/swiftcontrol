import 'package:bike_control/main.dart' show screenshotMode;
import 'package:shadcn_flutter/shadcn_flutter.dart';

/// The design's `bk-fade-up` entrance: fade in while sliding up ~12px over
/// 300ms. Give it a new [key] to re-run (the wizard keys it by step + phase).
/// Renders statically under reduced motion and in [screenshotMode] (which the
/// snapshot harness enables, keeping captures deterministic).
class OnboardingFadeUp extends StatelessWidget {
  const OnboardingFadeUp({super.key, required this.child, this.delay = Duration.zero});
  final Widget child;
  final Duration delay;

  @override
  Widget build(BuildContext context) {
    if (screenshotMode || MediaQuery.of(context).disableAnimations) return child;
    final total = const Duration(milliseconds: 300) + delay;
    final start = delay.inMilliseconds / total.inMilliseconds;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: total,
      curve: Interval(start, 1, curve: Curves.easeOutCubic),
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(offset: Offset(0, 12 * (1 - t)), child: child),
      ),
      child: child,
    );
  }
}
