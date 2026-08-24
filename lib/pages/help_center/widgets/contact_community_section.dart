// "Contact & community" section body — Reddit/Facebook/GitHub links plus the
// support-chat entry point, lifted unchanged from the old help-button
// dropdown's `MenuButton` (Task 8): unread-dot polling, the pre-staged
// overview screenshot, and the debug-text/TelemetrySnapshot handoff into
// `SupportChatPage` all behave exactly as before.
import 'package:bike_control/main.dart' show recordError;
import 'package:bike_control/pages/support_chat/support_chat_page.dart';
import 'package:bike_control/services/overview_screenshot.dart';
import 'package:bike_control/services/support_chat_models.dart';
import 'package:bike_control/services/support_chat_service.dart';
import 'package:bike_control/services/telemetry_snapshot.dart';
import 'package:bike_control/utils/core.dart';
import 'package:bike_control/utils/i18n_extension.dart';
import 'package:bike_control/widgets/menu.dart' show debugText;
import 'package:bike_control/widgets/ui/unread_dot.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:url_launcher/url_launcher_string.dart';

class ContactCommunitySection extends StatefulWidget {
  const ContactCommunitySection({super.key});

  @override
  State<ContactCommunitySection> createState() => _ContactCommunitySectionState();
}

class _ContactCommunitySectionState extends State<ContactCommunitySection> {
  bool _hasUnread = false;

  @override
  void initState() {
    super.initState();
    if (core.settings.getSupportChatActive()) {
      _checkForUnread();
    }
  }

  /// Polls the support chat in the background and surfaces a small dot next
  /// to "Chat with Support" when at least one admin message has arrived
  /// since the last seen timestamp on the chat. Failures (no auth, network
  /// down, edge function unavailable) are swallowed — the dot just stays off.
  Future<void> _checkForUnread() async {
    if (core.supabase.auth.currentSession == null) return;
    try {
      final fetched = await SupportChatService().fetchChat(skipLastSeen: true);
      if (!mounted) return;
      final lastSeen = fetched.chat?.lastSeenAt;
      final hasUnreadAdminReply = fetched.messages.any(
        (m) => m.senderRole == SupportMessageSenderRole.admin && (lastSeen == null || m.createdAt.isAfter(lastSeen)),
      );
      if (hasUnreadAdminReply != _hasUnread) {
        setState(() => _hasUnread = hasUnreadAdminReply);
      }
    } catch (e, s) {
      // Best-effort — leave the dot off.
      recordError(e, s, context: 'ContactCommunitySection.checkForUnread');
    }
  }

  Future<void> _openChat(BuildContext context) async {
    final screenshot = await captureOverviewScreenshot(context: context);
    if (!context.mounted) return;
    // Gather diagnostics in the background so the chat opens immediately; the
    // page awaits this future lazily for the preview. Send-time telemetry is
    // re-gathered fresh (see telemetryBuilder) so a later message reflects
    // the current state, not the compose-time snapshot.
    final debugFuture = debugText();
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SupportChatPage(
          diagnosticPreviewFuture: debugFuture,
          initialAttachment: screenshot,
          telemetryBuilder: () async => TelemetrySnapshot.general(freetext: await debugText()),
        ),
      ),
    );
    if (mounted) {
      setState(() => _hasUnread = false);
      _checkForUnread();
    }
  }

  @override
  Widget build(BuildContext context) {
    final destructive = Theme.of(context).colorScheme.destructive;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Button.ghost(
          onPressed: () => launchUrlString('https://www.reddit.com/r/BikeControl/'),
          child: Basic(
            leading: const Icon(Icons.reddit_outlined, size: 18),
            title: const Text('Reddit'),
            trailing: const Icon(Icons.chevron_right, size: 16).iconMutedForeground,
          ),
        ),
        Button.ghost(
          onPressed: () => launchUrlString('https://www.facebook.com/groups/1892836898778912'),
          child: Basic(
            leading: const Icon(Icons.facebook_outlined, size: 18),
            title: const Text('Facebook'),
            trailing: const Icon(Icons.chevron_right, size: 16).iconMutedForeground,
          ),
        ),
        Button.ghost(
          onPressed: () => launchUrlString('https://github.com/OpenBikeControl/bikecontrol/issues'),
          child: Basic(
            leading: const Icon(RadixIcons.githubLogo, size: 18),
            title: const Text('GitHub'),
            trailing: const Icon(Icons.chevron_right, size: 16).iconMutedForeground,
          ),
        ),
        Button.ghost(
          key: const ValueKey('help-center-chat-with-support'),
          onPressed: () => _openChat(context),
          child: Basic(
            leading: Icon(LucideIcons.messageCircle, size: 18, color: _hasUnread ? destructive : null),
            title: _hasUnread ? Text(context.i18n.chatWithSupport).semiBold : Text(context.i18n.chatWithSupport),
            trailing: _hasUnread
                ? const UnreadDot(key: ValueKey('help-center-chat-unread-dot'), size: 10)
                : const Icon(Icons.chevron_right, size: 16).iconMutedForeground,
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(left: 12, top: 2),
          child: Text(context.i18n.helpCenterChatLanguageHint).xSmall.muted,
        ),
      ],
    );
  }
}
