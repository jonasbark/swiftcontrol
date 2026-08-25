// "Known issues" section body (Task 10) — reuses
// `SupportChatService.fetchOpenIssues()`, the same public-issues fetch the
// support-chat intake screen already uses, so the two surfaces never drift
// into separate issue lists. Each row deep-links to the public issue page
// (`https://bikecontrol.app/issues/<id>`). Issues that carry a
// `helpBlogSlug` are "Blog-derived seeds" (website migration
// 20260517070000_seed_intake_help_issues.sql) — tutorial/help entries meant
// for the support intake form's "Read tutorial" affordance, not incidents —
// so this section excludes them outright rather than listing them (Bug 2;
// this superseded an earlier version that routed them to
// `https://bikecontrol.app/blog/<slug>` instead). An empty result or a fetch
// failure hides the section body entirely — no dead "no known issues" card
// — while still funneling failures through `recordError` per house rule.
import 'dart:async';

import 'package:bike_control/main.dart' show recordError;
import 'package:bike_control/services/support_chat_models.dart';
import 'package:bike_control/services/support_chat_service.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:url_launcher/url_launcher_string.dart';

class KnownIssuesSection extends StatefulWidget {
  /// Test seam: replaces the default `SupportChatService().fetchOpenIssues`
  /// call — see help_center_sections_test.dart.
  final Future<List<SupportIssue>> Function()? fetchIssues;

  const KnownIssuesSection({super.key, this.fetchIssues});

  @override
  State<KnownIssuesSection> createState() => _KnownIssuesSectionState();
}

class _KnownIssuesSectionState extends State<KnownIssuesSection> {
  List<SupportIssue> _issues = const [];

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final fetch = widget.fetchIssues ?? () => SupportChatService().fetchOpenIssues();
      final issues = await fetch();
      // Blog-derived seeds (helpBlogSlug set) are tutorial content for the
      // support intake form, not incidents — keep them out of this list. See
      // the file header comment for the full story (Bug 2).
      final filtered = issues.where((i) => i.helpBlogSlug == null || i.helpBlogSlug!.isEmpty).toList(growable: false);
      if (!mounted) return;
      setState(() => _issues = filtered);
    } catch (e, s) {
      // Supplementary content — a failed fetch just leaves the section
      // hidden (see build()), but it still must not be swallowed silently.
      recordError(e, s, context: 'KnownIssuesSection._load');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_issues.isEmpty) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    // Matches the mockup's row padding (`padding:11px 14px`) now that the
    // card itself carries no padding — rows run edge-to-edge and supply
    // their own inset.
    final rowStyle = ButtonStyle.ghost().withPadding(padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 14));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < _issues.length; i++) ...[
          if (i > 0) const Divider(),
          Button.ghost(
            style: rowStyle,
            onPressed: () => launchUrlString(_urlFor(_issues[i]), mode: LaunchMode.externalApplication),
            child: Basic(
              leading: const Icon(LucideIcons.triangleAlert, size: 18),
              title: Text(_issues[i].title, maxLines: 2, overflow: TextOverflow.ellipsis),
              trailing: Icon(LucideIcons.externalLink, size: 14, color: cs.mutedForeground),
            ),
          ),
        ],
      ],
    );
  }

  // Blog-derived (helpBlogSlug) issues never reach here — see _load() —
  // so every row still shown always deep-links to the plain issue page.
  String _urlFor(SupportIssue issue) => 'https://bikecontrol.app/issues/${issue.id}';
}
