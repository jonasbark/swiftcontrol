// "Known issues" section body (Task 10) — reuses
// `SupportChatService.fetchOpenIssues()`, the same public-issues fetch the
// support-chat intake screen already uses, so the two surfaces never drift
// into separate issue lists. Each row deep-links to the public issue page
// (`https://bikecontrol.app/issues/<id>`); an empty result or a fetch
// failure hides the section body entirely — no dead "no known issues" card —
// while still funneling failures through `recordError` per house rule.
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
      if (!mounted) return;
      setState(() => _issues = issues);
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final issue in _issues)
          Button.ghost(
            onPressed: () => launchUrlString(
              'https://bikecontrol.app/issues/${issue.id}',
              mode: LaunchMode.externalApplication,
            ),
            child: Basic(
              leading: const Icon(LucideIcons.triangleAlert, size: 18),
              title: Text(issue.title, maxLines: 2, overflow: TextOverflow.ellipsis),
              trailing: Icon(LucideIcons.externalLink, size: 14, color: cs.mutedForeground),
            ),
          ),
      ],
    );
  }
}
