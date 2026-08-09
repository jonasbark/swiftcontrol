import 'package:bike_control/utils/i18n_extension.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

/// "Press a button on your controller to continue … or tap here".
/// The actual advance-on-hardware-press lives in the page's actionStream
/// listener; this widget is the visual + tap fallback.
class OnboardingButtonHint extends StatefulWidget {
  const OnboardingButtonHint({super.key, required this.onContinue});
  final VoidCallback onContinue;

  @override
  State<OnboardingButtonHint> createState() => _OnboardingButtonHintState();
}

class _OnboardingButtonHintState extends State<OnboardingButtonHint> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1600));
  bool _startedPulse = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_startedPulse && !MediaQuery.of(context).disableAnimations) {
      _startedPulse = true;
      _pulse.repeat();
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Button.ghost(
      onPressed: widget.onContinue,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          border: Border.all(color: scheme.primary, width: 1.5),
          borderRadius: BorderRadius.circular(12),
          color: scheme.primary.withValues(alpha: 0.08),
        ),
        child: Row(children: [
          AnimatedBuilder(
            animation: _pulse,
            builder: (context, child) => Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: scheme.primary,
                boxShadow: [
                  BoxShadow(
                    color: scheme.primary.withValues(alpha: (1 - _pulse.value) * 0.45),
                    spreadRadius: _pulse.value * 10,
                  ),
                ],
              ),
              child: const Icon(LucideIcons.chevronUp, size: 17, color: Color(0xFFFFFFFF)),
            ),
          ),
          Gap(12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(context.i18n.onboardingPressButtonToContinue).small.semiBold,
              Text(context.i18n.onboardingOrTapHere).xSmall.muted,
            ]),
          ),
        ]),
      ),
    );
  }
}
