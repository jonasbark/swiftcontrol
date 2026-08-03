import 'package:bike_control/main.dart';
import 'package:bike_control/utils/click_v2_onboarding.dart';
import 'package:bike_control/utils/i18n_extension.dart';
import 'package:bike_control/widgets/click_v2/click_contours.dart';
import 'package:flutter/widgets.dart' show PageView, PageController;
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:url_launcher/url_launcher_string.dart';

const _whyUrl = 'https://bikecontrol.app/blog/zwift-click-v2-with-other-trainer-apps/';
const _alternativesUrl = 'https://bikecontrol.app/blog/best-controller-for-indoor-cycling/';

/// The one-time Zwift Click V2 unlock-mode explainer.
///
/// Zwift locks the Click V2 to their own app, and the two workarounds
/// BikeControl offers are a genuine trade-off rather than a right answer — so
/// this lays both out side by side before anything connects. Discovered
/// controllers stay out of the connect queue until a choice lands here.
class ClickV2OnboardingPage extends StatefulWidget {
  const ClickV2OnboardingPage({super.key});

  @override
  State<ClickV2OnboardingPage> createState() => _ClickV2OnboardingPageState();
}

class _ClickV2OnboardingPageState extends State<ClickV2OnboardingPage> with SingleTickerProviderStateMixin {
  final _controller = PageController();
  double _page = 0;
  bool _submitting = false;

  // Drives the pro/con rows' one-shot staggered entrance. PageView (without a
  // builder) constructs both option pages eagerly, so this fires for both at
  // load time rather than when a page actually becomes active.
  late final AnimationController _rows = AnimationController(vsync: this, duration: const Duration(milliseconds: 420))..forward();

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onScroll);
  }

  void _onScroll() {
    // The hero interpolates on the fractional page value so a swipe scrubs it
    // continuously instead of snapping at the page boundary.
    final page = _controller.page;
    if (page != null && page != _page) {
      setState(() => _page = page);
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onScroll);
    _controller.dispose();
    _rows.dispose();
    super.dispose();
  }

  Future<void> _choose(Future<void> Function() apply) async {
    // Two fast taps would otherwise both re-enter this before the first
    // await resolves; the writes are idempotent but it's wasted racy work.
    if (_submitting) return;
    setState(() => _submitting = true);
    try {
      await apply();
    } catch (e, stack) {
      recordError(e, stack, context: 'ClickV2OnboardingPage.choose');
    }
    if (!mounted) return;
    final popped = await Navigator.of(context).maybePop();
    if (!popped && mounted) {
      // Nothing to pop back to (e.g. this page is the root) — re-enable the
      // CTAs rather than leaving them permanently disabled.
      setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.i18n;
    return Scaffold(
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 8,
                children: [
                  Row(
                    children: [
                      Expanded(child: Text(l10n.clickV2Onboarding_title).large.semiBold),
                      IconButton.ghost(
                        key: const ValueKey('click-onboarding-close'),
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.of(context).maybePop(),
                      ),
                    ],
                  ),
                  Text(l10n.clickV2Onboarding_intro).small.muted,
                  Button.link(
                    onPressed: () => launchUrlString(_whyUrl),
                    trailing: const Icon(Icons.open_in_new, size: 14),
                    child: Text(l10n.clickV2Onboarding_whyLink),
                  ),
                ],
              ),
            ),
            const Gap(12),
            SizedBox(
              height: 180,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: ClickContours(page: _page),
              ),
            ),
            const Gap(12),
            Expanded(
              child: PageView(
                controller: _controller,
                children: [
                  _option(
                    title: l10n.clickV2Onboarding_leftOnlyTitle,
                    pros: [l10n.clickV2Onboarding_leftOnlyPro1, l10n.clickV2Onboarding_leftOnlyPro2],
                    cons: [l10n.clickV2Onboarding_leftOnlyCon1, l10n.clickV2Onboarding_leftOnlyCon2],
                    cta: l10n.clickV2Onboarding_leftOnlyCta,
                    onPressed: () => _choose(ClickV2Onboarding.chooseLeftSideOnly),
                  ),
                  _option(
                    title: l10n.clickV2Onboarding_zwiftTitle,
                    pros: [l10n.clickV2Onboarding_zwiftPro1, l10n.clickV2Onboarding_zwiftPro2],
                    cons: [l10n.clickV2Onboarding_zwiftCon1, l10n.clickV2Onboarding_zwiftCon2],
                    cta: l10n.clickV2Onboarding_zwiftCta,
                    onPressed: () => _choose(ClickV2Onboarding.chooseUnlockWithZwift),
                  ),
                ],
              ),
            ),
            Center(child: _dots()),
            const Gap(8),
            const Divider(),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: Button.link(
                onPressed: () => launchUrlString(_alternativesUrl),
                trailing: const Icon(Icons.open_in_new, size: 14),
                child: Text(l10n.clickV2Onboarding_alternativesLink),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dots() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      spacing: 8,
      children: [
        for (var i = 0; i < 2; i++)
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: (_page.round() == i
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).colorScheme.mutedForeground.withValues(alpha: 0.4)),
            ),
          ),
      ],
    );
  }

  // The pros/cons list scrolls if it doesn't fit; the CTA is a fixed sibling
  // below it so it's always reachable regardless of how tall that list gets
  // (long localized strings, a future badge, etc.) — never itself scrolled
  // out of view.
  Widget _option({
    required String title,
    required List<String> pros,
    required List<String> cons,
    required String cta,
    required VoidCallback onPressed,
  }) {
    final rows = [...pros, ...cons];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 12,
                children: [
                  Text(title).large.semiBold,
                  for (var index = 0; index < rows.length; index++)
                    _row(rows[index], isPro: index < pros.length, index: index),
                ],
              ),
            ),
          ),
          const Gap(4),
          SizedBox(
            width: double.infinity,
            child: Button.primary(onPressed: _submitting ? null : onPressed, child: Text(cta)),
          ),
          const Gap(12),
        ],
      ),
    );
  }

  Widget _row(String text, {required bool isPro, required int index}) {
    // Rows fade in and rise 8px, 60ms apart in order — enough to read as a
    // sequence without making the rider wait for it.
    final start = (index * 0.15).clamp(0.0, 0.6);
    final curve = CurvedAnimation(parent: _rows, curve: Interval(start, 1, curve: Curves.easeOut));
    return FadeTransition(
      opacity: curve,
      child: SlideTransition(
        position: Tween(begin: const Offset(0, 0.18), end: Offset.zero).animate(curve),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 8,
          children: [
            Icon(
              isPro ? Icons.check_circle_outline : Icons.remove_circle_outline,
              size: 16,
              color: isPro ? Colors.green : Theme.of(context).colorScheme.mutedForeground,
            ),
            Expanded(child: Text(text).small),
          ],
        ),
      ),
    );
  }
}
