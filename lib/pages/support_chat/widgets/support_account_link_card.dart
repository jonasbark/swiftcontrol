import 'package:bike_control/gen/l10n.dart';
import 'package:bike_control/main.dart' show recordError;
import 'package:bike_control/services/feedback_submission_service.dart';
import 'package:bike_control/widgets/ui/small_progress_indicator.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

/// Inline "Get the reply" card offering to link an email address to the
/// rider's anonymous support-chat session — the same two-phase flow
/// (email → 6-digit code → linked) as `FeedbackThanksStep`, reusing
/// [FeedbackSubmissionService] for the actual Supabase calls since the
/// account-linking logic isn't feedback-specific.
///
/// [SupportChatPage] has two entry points that reveal this widget — the
/// post-send prompt and the header's "Sign In" button — and both converge on
/// this one instance, so there is exactly one state machine regardless of
/// which one the rider used.
class SupportAccountLinkCard extends StatefulWidget {
  final FeedbackSubmissionService accountService;

  /// Called once, right after [FeedbackSubmissionService.confirmEmailLink]
  /// succeeds, so the parent can refresh anything that reads
  /// [FeedbackSubmissionService.isAnonymous] itself (the chat header).
  final VoidCallback? onLinked;

  const SupportAccountLinkCard({super.key, required this.accountService, this.onLinked});

  @override
  State<SupportAccountLinkCard> createState() => _SupportAccountLinkCardState();
}

class _SupportAccountLinkCardState extends State<SupportAccountLinkCard> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _codeController = TextEditingController();

  /// Null until [_sendLink] succeeds — then holds the address the code was
  /// sent to and the UI switches from the email field to the code field.
  String? _codeSentTo;
  bool _linked = false;
  bool _busy = false;
  bool _failed = false;

  @override
  void dispose() {
    _emailController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _sendLink() async {
    final email = _emailController.text.trim();
    if (email.isEmpty || _busy) return;
    setState(() {
      _busy = true;
      _failed = false;
    });
    try {
      await widget.accountService.beginEmailLink(email);
      if (!mounted) return;
      setState(() {
        _codeSentTo = email;
        _busy = false;
      });
    } catch (e, s) {
      await recordError(e, s, context: 'SupportAccountLinkCard.beginEmailLink');
      if (!mounted) return;
      setState(() {
        _busy = false;
        _failed = true;
      });
    }
  }

  Future<void> _verify() async {
    final email = _codeSentTo;
    final code = _codeController.text.trim();
    if (email == null || code.isEmpty || _busy) return;
    setState(() {
      _busy = true;
      _failed = false;
    });
    try {
      await widget.accountService.confirmEmailLink(email: email, token: code);
      if (!mounted) return;
      setState(() {
        _linked = true;
        _busy = false;
      });
      widget.onLinked?.call();
    } catch (e, s) {
      await recordError(e, s, context: 'SupportAccountLinkCard.confirmEmailLink');
      if (!mounted) return;
      setState(() {
        _busy = false;
        _failed = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;

    if (_linked) {
      return Container(
        key: const ValueKey('support-account-linked'),
        margin: const EdgeInsets.fromLTRB(12, 6, 12, 0),
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: Colors.green.withAlpha(20),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.green),
        ),
        child: Row(
          children: [
            const Icon(LucideIcons.check, size: 16, color: Colors.green),
            const Gap(9),
            Expanded(
              child: Text(
                l10n.supportAccountLinkedNote,
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      key: const ValueKey('support-account-link-card'),
      margin: const EdgeInsets.fromLTRB(12, 6, 12, 0),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: cs.muted.withAlpha(120),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l10n.supportAccountLinkTitle, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          const Gap(3),
          Text(l10n.supportAccountLinkBody, style: TextStyle(fontSize: 12.5, color: cs.mutedForeground)),
          const Gap(11),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: _codeSentTo == null
                    ? TextField(
                        key: const ValueKey('support-account-email-field'),
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        placeholder: Text(l10n.emailAddress),
                      )
                    : TextField(
                        key: const ValueKey('support-account-code-field'),
                        controller: _codeController,
                        keyboardType: TextInputType.number,
                        placeholder: Text(l10n.feedbackEmailCodeHint),
                      ),
              ),
              const Gap(8),
              PrimaryButton(
                key: ValueKey(_codeSentTo == null ? 'support-account-email-send' : 'support-account-code-verify'),
                onPressed: _busy ? null : (_codeSentTo == null ? _sendLink : _verify),
                child: _busy
                    ? const SmallProgressIndicator()
                    : Text(_codeSentTo == null ? l10n.supportAccountLinkAddButton : l10n.feedbackEmailVerifyButton),
              ),
            ],
          ),
          if (_failed) ...[
            const Gap(8),
            Text(
              l10n.supportAccountLinkFailed,
              style: TextStyle(color: cs.destructive, fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }
}
