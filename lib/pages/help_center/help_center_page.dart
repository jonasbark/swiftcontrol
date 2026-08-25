// The Help Center page: a persistent, scrollable page of sections, replacing
// the old help-button dropdown. Guides & videos, Your setup, Known issues,
// Pricing & account, and Contact & community all live here as separate
// section widgets — see each one's own file for its history. (Design round
// 1 dropped the standalone Troubleshooting section — "Get help" from the
// feedback prompt and the guides/known-issues/support sections here now
// cover that ground — and replaced the blog link in "Guides & videos" with
// a direct Tutorials link.)
import 'dart:async';

import 'package:bike_control/main.dart' show recordError;
import 'package:bike_control/pages/help_center/widgets/contact_community_section.dart';
import 'package:bike_control/pages/help_center/widgets/guides_videos_section.dart';
import 'package:bike_control/pages/help_center/widgets/help_center_section_card.dart';
import 'package:bike_control/pages/help_center/widgets/known_issues_section.dart';
import 'package:bike_control/pages/help_center/widgets/pricing_faq_section.dart';
import 'package:bike_control/pages/help_center/widgets/your_setup_section.dart';
import 'package:bike_control/utils/i18n_extension.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

/// A section the page can be asked to land the rider on directly, e.g. from a
/// "check your setup" hint elsewhere in the app.
enum HelpCenterFocus { yourSetup }

class HelpCenterPage extends StatefulWidget {
  final HelpCenterFocus? focus;

  const HelpCenterPage({super.key, this.focus});

  @override
  State<HelpCenterPage> createState() => _HelpCenterPageState();
}

class _HelpCenterPageState extends State<HelpCenterPage> {
  final GlobalKey _yourSetupKey = GlobalKey();
  bool _yourSetupExpanded = false;

  @override
  void initState() {
    super.initState();
    if (widget.focus == HelpCenterFocus.yourSetup) {
      _yourSetupExpanded = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _revealYourSetup());
    }
  }

  /// Scrolls the "Your setup" section into view. No-op when the section
  /// isn't in the tree yet (first frame raced the layout).
  void _revealYourSetup() {
    final ctx = _yourSetupKey.currentContext;
    if (!mounted || ctx == null) return;
    try {
      unawaited(
        Scrollable.ensureVisible(
          ctx,
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeInOut,
          alignment: 0.1,
        ),
      );
    } catch (e, s) {
      recordError(e, s, context: 'HelpCenterPage._revealYourSetup');
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.i18n;

    final sections = <Widget>[
      HelpCenterSectionCard(
        index: 0,
        icon: LucideIcons.bookOpen,
        title: l10n.helpCenterGuides,
        child: const GuidesVideosSection(),
      ),
      HelpCenterSectionCard(
        key: _yourSetupKey,
        index: 1,
        icon: LucideIcons.settings2,
        title: l10n.helpCenterYourSetup,
        child: _YourSetupFocusFrame(
          key: const ValueKey('help-your-setup'),
          expanded: _yourSetupExpanded,
          child: const YourSetupSection(),
        ),
      ),
      HelpCenterSectionCard(
        index: 2,
        icon: LucideIcons.triangleAlert,
        title: l10n.helpCenterKnownIssues,
        child: const KnownIssuesSection(key: ValueKey('help-known-issues')),
      ),
      HelpCenterSectionCard(
        index: 3,
        icon: LucideIcons.creditCard,
        title: l10n.helpCenterPricingFaq,
        child: const PricingFaqSection(key: ValueKey('help-pricing-account')),
      ),
      HelpCenterSectionCard(
        index: 4,
        icon: LucideIcons.users,
        title: l10n.helpCenterContact,
        child: const ContactCommunitySection(),
      ),
    ];

    return Scaffold(
      headers: [
        AppBar(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          leading: [
            IconButton.ghost(
              icon: const Icon(LucideIcons.arrowLeft, size: 22),
              onPressed: () => Navigator.of(context).maybePop(),
            ),
          ],
          title: Text(
            l10n.helpCenterTitle,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, letterSpacing: -0.3),
          ),
          backgroundColor: Theme.of(context).colorScheme.background,
        ),
        const Divider(),
      ],
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 700),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 12,
              children: sections,
            ),
          ),
        ),
      ),
    );
  }
}

/// Wraps [YourSetupSection] with a highlighted-border cue so a rider landing
/// on this page via `HelpCenterFocus.yourSetup` gets a visual "you're here"
/// nudge (Task 9).
class _YourSetupFocusFrame extends StatelessWidget {
  final bool expanded;
  final Widget child;

  const _YourSetupFocusFrame({super.key, required this.child, this.expanded = false});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: expanded ? cs.primary : cs.mutedForeground.withValues(alpha: 0.3),
          width: expanded ? 1.2 : 0.3,
        ),
      ),
      child: child,
    );
  }
}
