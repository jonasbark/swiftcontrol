import 'package:bike_control/gen/l10n.dart';
import 'package:bike_control/main.dart' show recordError;
import 'package:bike_control/services/feedback_prompt_service.dart';
import 'package:bike_control/services/feedback_submission_service.dart';
import 'package:bike_control/widgets/ui/small_progress_indicator.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

/// Free-text composer for the feedback flow — used for both the positive
/// (suggestion) and negative (complaint) branches, distinguished by the
/// [sentiment]/[kind] pair it was opened with.
///
/// On a successful submit, [service] (the once-per-launch gate) is marked
/// completed and [onSubmitted] advances the flow to the thanks step. On
/// failure the typed text stays put and an inline retry row appears instead
/// of losing what the rider wrote.
class FeedbackComposerStep extends StatefulWidget {
  final FeedbackPromptService service;
  final FeedbackSubmissionService submissionService;
  final FeedbackSentiment sentiment;
  final FeedbackKind kind;
  final VoidCallback onSubmitted;

  const FeedbackComposerStep({
    super.key,
    required this.service,
    required this.submissionService,
    required this.sentiment,
    required this.kind,
    required this.onSubmitted,
  });

  @override
  State<FeedbackComposerStep> createState() => _FeedbackComposerStepState();
}

class _FeedbackComposerStepState extends State<FeedbackComposerStep> {
  final TextEditingController _controller = TextEditingController();
  bool _sending = false;
  bool _failed = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _canSend => !_sending && _controller.text.trim().isNotEmpty;

  Future<void> _send() async {
    if (!_canSend) return;
    setState(() {
      _sending = true;
      _failed = false;
    });
    try {
      await widget.submissionService.submit(
        sentiment: widget.sentiment,
        kind: widget.kind,
        body: _controller.text.trim(),
      );
      await widget.service.markCompleted();
      if (mounted) widget.onSubmitted();
    } catch (e, s) {
      await recordError(e, s, context: 'FeedbackComposerStep.send');
      if (mounted) {
        setState(() {
          _sending = false;
          _failed = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final hint = widget.kind == FeedbackKind.complaint
        ? l10n.feedbackComposerComplaintHint
        : l10n.feedbackComposerSuggestionHint;
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextArea(
            controller: _controller,
            placeholder: Text(hint),
            expandableHeight: true,
            initialHeight: 120,
            onChanged: (_) => setState(() {}),
          ),
          const Gap(8),
          Text(l10n.feedbackComposerAnonymousNote).muted.small,
          const Gap(16),
          PrimaryButton(
            key: const ValueKey('feedback-send'),
            onPressed: _canSend ? _send : null,
            child: _sending ? const SmallProgressIndicator() : Text(l10n.feedbackComposerSend),
          ),
          if (_failed) ...[
            const Gap(12),
            Text(
              l10n.feedbackSendFailed,
              textAlign: TextAlign.center,
              style: TextStyle(color: Theme.of(context).colorScheme.destructive),
            ).small,
            const Gap(8),
            Center(
              child: SecondaryButton(
                key: const ValueKey('feedback-retry'),
                onPressed: _send,
                child: Text(l10n.feedbackRetryButton),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
