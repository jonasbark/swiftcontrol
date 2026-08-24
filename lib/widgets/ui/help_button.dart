import 'package:bike_control/pages/help_center/help_center_page.dart';
import 'package:bike_control/services/support_chat_models.dart';
import 'package:bike_control/services/support_chat_service.dart';
import 'package:bike_control/utils/core.dart';
import 'package:bike_control/utils/i18n_extension.dart';
import 'package:prop/utils/shared.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

class HelpButton extends StatefulWidget {
  final bool isMobile;
  const HelpButton({super.key, required this.isMobile});

  @override
  State<HelpButton> createState() => _HelpButtonState();
}

class _HelpButtonState extends State<HelpButton> {
  bool _hasUnread = false;

  @override
  void initState() {
    super.initState();
    if (core.settings.getSupportChatActive()) {
      _checkForUnread();
    }
  }

  /// Polls the support chat in the background and surfaces a small dot on
  /// the help button when at least one admin message has arrived since the
  /// last seen timestamp on the chat. Failures (no auth, network down,
  /// edge function unavailable) are swallowed — the dot just stays off.
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
    } catch (error) {
      // Best-effort — leave the dot off.
      Logger.error('Failed to check for unread support messages $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = widget.isMobile;
    final border = isMobile
        ? BorderRadius.only(topRight: Radius.circular(8), topLeft: Radius.circular(8))
        : BorderRadius.only(bottomLeft: Radius.circular(8), bottomRight: Radius.circular(8));
    return Container(
      decoration: BoxDecoration(
        borderRadius: border,
      ),
      child: Builder(
        builder: (context) {
          return Button(
            onPressed: () => context.push(const HelpCenterPage()),
            leading: Padding(
              padding: EdgeInsets.only(
                bottom: isMobile
                    ? MediaQuery.viewPaddingOf(context).bottom / MediaQuery.devicePixelRatioOf(context)
                    : 0,
              ),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Icon(
                    LucideIcons.messageCircle,
                    color: _hasUnread ? Theme.of(context).colorScheme.destructive : null,
                  ),
                  if (_hasUnread)
                    const Positioned(
                      right: -8,
                      top: -8,
                      child: _PulsingUnreadBadge(),
                    ),
                ],
              ),
            ),
            style: ButtonStyle.secondary()
                .withBorderRadius(
                  borderRadius: border,
                  hoverBorderRadius: border,
                )
                .withBorder(
                  border: Border.all(
                    width: _hasUnread ? 1.2 : 0.3,
                    color: _hasUnread
                        ? Theme.of(context).colorScheme.destructive
                        : Theme.of(context).colorScheme.mutedForeground,
                  ),
                ),
            child: Padding(
              padding: EdgeInsets.only(
                bottom: isMobile
                    ? MediaQuery.viewPaddingOf(context).bottom / MediaQuery.devicePixelRatioOf(context)
                    : 0,
              ),
              child: Text(context.i18n.troubleshootingGuide),
            ),
          );
        },
      ),
    );
  }
}

class _UnreadDot extends StatelessWidget {
  const _UnreadDot();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.destructive,
        shape: BoxShape.circle,
        border: Border.all(
          color: Theme.of(context).colorScheme.background,
          width: 1.5,
        ),
      ),
    );
  }
}

/// Animated unread indicator: a red dot with a halo ring that pulses outward.
/// Used on the Help button's icon overlay so a new support reply is hard to miss.
class _PulsingUnreadBadge extends StatefulWidget {
  const _PulsingUnreadBadge();

  @override
  State<_PulsingUnreadBadge> createState() => _PulsingUnreadBadgeState();
}

class _PulsingUnreadBadgeState extends State<_PulsingUnreadBadge> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final destructive = Theme.of(context).colorScheme.destructive;
    final scaleTween = Tween<double>(begin: 1.0, end: 2.6).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );
    final opacityTween = Tween<double>(begin: 0.55, end: 0.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );

    return IgnorePointer(
      child: SizedBox(
        width: 24,
        height: 24,
        child: Stack(
          alignment: Alignment.center,
          children: [
            AnimatedBuilder(
              animation: _controller,
              builder: (_, _) => Transform.scale(
                scale: scaleTween.value,
                child: Opacity(
                  opacity: opacityTween.value,
                  child: Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: destructive,
                    ),
                  ),
                ),
              ),
            ),
            const _UnreadDot(),
          ],
        ),
      ),
    );
  }
}
