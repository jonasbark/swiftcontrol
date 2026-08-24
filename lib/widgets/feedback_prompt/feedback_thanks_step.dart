import 'package:bike_control/gen/l10n.dart';
import 'package:bike_control/main.dart' show recordError;
import 'package:bike_control/services/feedback_submission_service.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

/// Closing step of the feedback flow: a thank-you, an optional email
/// link-up for anonymous sessions (email → code → confirmed, two phases),
/// and — only for the suggestion branch — a ghost link back into the store
/// rating prompt. [onClosed] (wired to `Button.ghost` "skip") is the only
/// way out; there's no separate "done" affordance.
class FeedbackThanksStep extends StatefulWidget {
  final FeedbackSubmissionService submissionService;
  final FeedbackKind kind;
  final Future<void> Function() onRate;
  final VoidCallback onClosed;

  const FeedbackThanksStep({
    super.key,
    required this.submissionService,
    required this.kind,
    required this.onRate,
    required this.onClosed,
  });

  @override
  State<FeedbackThanksStep> createState() => _FeedbackThanksStepState();
}

class _FeedbackThanksStepState extends State<FeedbackThanksStep> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _codeController = TextEditingController();

  /// Null until [beginEmailLink] succeeds — then holds the address the code
  /// was sent to and the UI switches from the email field to the code field.
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
      await widget.submissionService.beginEmailLink(email);
      if (!mounted) return;
      setState(() {
        _codeSentTo = email;
        _busy = false;
      });
    } catch (e, s) {
      await recordError(e, s, context: 'FeedbackThanksStep.beginEmailLink');
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
      await widget.submissionService.confirmEmailLink(email: email, token: code);
      if (!mounted) return;
      setState(() {
        _linked = true;
        _busy = false;
      });
    } catch (e, s) {
      await recordError(e, s, context: 'FeedbackThanksStep.confirmEmailLink');
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
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l10n.feedbackThanksTitle, textAlign: TextAlign.center).semiBold,
          const Gap(8),
          Text(l10n.feedbackThanksBody, textAlign: TextAlign.center).muted,
          if (_linked) ...[
            const Gap(20),
            Text(l10n.feedbackEmailLinked, textAlign: TextAlign.center),
          ] else if (widget.submissionService.isAnonymous) ...[
            const Gap(20),
            ..._buildEmailLinkUp(l10n),
          ],
          if (widget.kind == FeedbackKind.suggestion) ...[
            const Gap(12),
            Center(
              child: Button.ghost(
                key: const ValueKey('feedback-also-rate'),
                onPressed: () => widget.onRate(),
                child: Text(l10n.feedbackAlsoRateLink),
              ),
            ),
          ],
          const Gap(12),
          Center(
            child: Button.ghost(
              key: const ValueKey('feedback-skip'),
              onPressed: widget.onClosed,
              child: Text(l10n.feedbackSkipButton),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildEmailLinkUp(AppLocalizations l10n) {
    final children = <Widget>[
      Text(l10n.feedbackEmailLinkPrompt, textAlign: TextAlign.center).small,
      const Gap(8),
    ];

    if (_codeSentTo == null) {
      children.addAll([
        TextField(
          key: const ValueKey('feedback-email-field'),
          controller: _emailController,
          keyboardType: TextInputType.emailAddress,
          placeholder: Text(l10n.emailAddress),
        ),
        const Gap(8),
        PrimaryButton(
          key: const ValueKey('feedback-email-send'),
          onPressed: _busy ? null : _sendLink,
          child: Text(l10n.feedbackEmailLinkButton),
        ),
      ]);
    } else {
      children.addAll([
        TextField(
          key: const ValueKey('feedback-email-code-field'),
          controller: _codeController,
          keyboardType: TextInputType.number,
          placeholder: Text(l10n.feedbackEmailCodeHint),
        ),
        const Gap(8),
        PrimaryButton(
          key: const ValueKey('feedback-email-verify'),
          onPressed: _busy ? null : _verify,
          child: Text(l10n.feedbackEmailVerifyButton),
        ),
      ]);
    }

    if (_failed) {
      children.addAll([
        const Gap(8),
        Text(
          l10n.feedbackSendFailed,
          textAlign: TextAlign.center,
          style: TextStyle(color: Theme.of(context).colorScheme.destructive),
        ).small,
      ]);
    }

    return children;
  }
}
