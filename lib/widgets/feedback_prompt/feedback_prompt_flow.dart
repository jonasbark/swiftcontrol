import 'package:bike_control/gen/l10n.dart';
import 'package:bike_control/services/feedback_prompt_service.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

/// Steps of the feedback prompt flow. `gate` asks a plain thumbs up/down
/// sentiment question (no rating, no stars); `positive`/`negative` branch off
/// it; `composer`/`negative` eventually lead into `composer` (free-text) and
/// `thanks`. Only `gate` is fully built out here — the rest are placeholders
/// wired up by later tasks.
enum FeedbackFlowStep { gate, positive, negative, composer, thanks }

/// Opens the feedback prompt flow: a bottom sheet on narrow layouts
/// (`width < 600`) or a centered dialog otherwise.
///
/// The presentation mechanism decides how the flow closes itself — a sheet
/// closes via [closeDrawer], a dialog via [Navigator.pop] — so this wires the
/// right `onClose` into [FeedbackPromptFlow] for each case.
Future<void> showFeedbackPromptFlow(
  BuildContext context, {
  required FeedbackPromptService service,
  FeedbackFlowStep initialStep = FeedbackFlowStep.gate,
}) async {
  final isMobile = MediaQuery.sizeOf(context).width < 600;
  if (isMobile) {
    await openDrawer(
      context: context,
      position: OverlayPosition.bottom,
      builder: (sheetContext) => FeedbackPromptFlow(
        service: service,
        initialStep: initialStep,
        onClose: () => closeDrawer(sheetContext),
      ),
    );
  } else {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          // shadcn's own ModalContainer — not a hand-rolled one — so this
          // stays consistent with the rest of the app's dialog chrome.
          child: ModalContainer(
            filled: true,
            padding: const EdgeInsets.all(20),
            child: FeedbackPromptFlow(
              service: service,
              initialStep: initialStep,
              onClose: () => Navigator.of(dialogContext).pop(),
            ),
          ),
        ),
      ),
    );
  }
}

/// Renders the current step of the feedback prompt flow, cross-fading and
/// sliding between steps.
///
/// Pumped directly in widget tests without going through
/// [showFeedbackPromptFlow] — in that case there is no ambient dialog/drawer
/// route, so [onClose] is null and closing becomes a no-op instead of
/// crashing or popping an unrelated route.
class FeedbackPromptFlow extends StatefulWidget {
  final FeedbackPromptService service;
  final FeedbackFlowStep initialStep;
  final VoidCallback? onClose;

  const FeedbackPromptFlow({
    super.key,
    required this.service,
    this.initialStep = FeedbackFlowStep.gate,
    this.onClose,
  });

  /// Guards against showing the gate more than once per app launch. Reset
  /// only by an app restart in production.
  static bool shownThisLaunch = false;

  /// Test-only escape hatch: resets [shownThisLaunch] so tests don't leak
  /// the once-per-launch guard into each other. Never call from app code.
  @visibleForTesting
  static void resetShownThisLaunchForTesting() => shownThisLaunch = false;

  @override
  State<FeedbackPromptFlow> createState() => _FeedbackPromptFlowState();
}

/// Wires [FeedbackPromptService.shouldShowPrompt] to a single, once-per-launch
/// [onShow] callback.
///
/// Extracted out of `OverviewPage` so the "already-eligible-at-attach" edge
/// case is independently testable: `service.start()` (in `_Starter.initState`,
/// higher in the tree than the page that owns this trigger) can synchronously
/// set `shouldShowPrompt.value = true` *before* this trigger attaches, e.g.
/// when the session threshold was already crossed in a previous launch. A
/// bare `addListener` only fires on a value *change*, so that already-true
/// state would otherwise never surface the prompt — call [checkInitial] once
/// right after construction to also cover that case.
class FeedbackPromptTrigger {
  final FeedbackPromptService service;
  final VoidCallback onShow;

  FeedbackPromptTrigger({required this.service, required this.onShow}) {
    service.shouldShowPrompt.addListener(_onChanged);
  }

  void _onChanged() {
    if (!service.shouldShowPrompt.value) return;
    if (FeedbackPromptFlow.shownThisLaunch) return;
    FeedbackPromptFlow.shownThisLaunch = true;
    onShow();
  }

  /// Fires [onShow] immediately if [service] is already eligible. Safe to
  /// call unconditionally right after attaching — it's a no-op otherwise.
  void checkInitial() => _onChanged();

  void dispose() {
    service.shouldShowPrompt.removeListener(_onChanged);
  }
}

class _FeedbackPromptFlowState extends State<FeedbackPromptFlow> {
  late FeedbackFlowStep _step;

  @override
  void initState() {
    super.initState();
    _step = widget.initialStep;
  }

  void _goTo(FeedbackFlowStep step) {
    if (!mounted) return;
    setState(() => _step = step);
  }

  void _close() {
    final onClose = widget.onClose;
    if (onClose != null) {
      onClose();
    } else if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _onNotNow() async {
    await widget.service.dismiss();
    _close();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position: Tween<Offset>(begin: const Offset(0, 0.05), end: Offset.zero).animate(animation),
          child: child,
        ),
      ),
      child: KeyedSubtree(
        key: ValueKey('feedback-step-${_step.name}'),
        child: _buildStep(context),
      ),
    );
  }

  Widget _buildStep(BuildContext context) {
    switch (_step) {
      case FeedbackFlowStep.gate:
        return _GateStep(
          onPositive: () => _goTo(FeedbackFlowStep.positive),
          onNegative: () => _goTo(FeedbackFlowStep.negative),
          onNotNow: _onNotNow,
        );
      case FeedbackFlowStep.positive:
      case FeedbackFlowStep.negative:
      case FeedbackFlowStep.composer:
      case FeedbackFlowStep.thanks:
        // Placeholders: Tasks 4/7/8 build these out. For now they simply
        // record that feedback happened and close the flow.
        return _PlaceholderStep(service: widget.service, onClosed: _close);
    }
  }
}

class _GateStep extends StatelessWidget {
  final VoidCallback onPositive;
  final VoidCallback onNegative;
  final Future<void> Function() onNotNow;

  const _GateStep({
    required this.onPositive,
    required this.onNegative,
    required this.onNotNow,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l10n.feedbackPromptTitle, textAlign: TextAlign.center).semiBold,
          const Gap(20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              Button.outline(
                key: const ValueKey('feedback-thumbs-up'),
                style: const ButtonStyle.outline(size: ButtonSize.large),
                onPressed: onPositive,
                child: const Icon(Icons.thumb_up_outlined, size: 28),
              ),
              Button.outline(
                key: const ValueKey('feedback-thumbs-down'),
                style: const ButtonStyle.outline(size: ButtonSize.large),
                onPressed: onNegative,
                child: const Icon(Icons.thumb_down_outlined, size: 28),
              ),
            ],
          ),
          const Gap(12),
          Center(
            child: Button.ghost(
              key: const ValueKey('feedback-not-now'),
              onPressed: () => onNotNow(),
              child: Text(l10n.feedbackPromptNotNow),
            ),
          ),
        ],
      ),
    );
  }
}

/// Stands in for the positive/negative/composer/thanks steps until later
/// tasks build them out. Marks feedback as handled and closes the flow so
/// the gate never blocks the app even before the rest of the flow lands.
class _PlaceholderStep extends StatefulWidget {
  final FeedbackPromptService service;
  final VoidCallback onClosed;

  const _PlaceholderStep({required this.service, required this.onClosed});

  @override
  State<_PlaceholderStep> createState() => _PlaceholderStepState();
}

class _PlaceholderStepState extends State<_PlaceholderStep> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _complete());
  }

  Future<void> _complete() async {
    await widget.service.markCompleted();
    if (mounted) widget.onClosed();
  }

  @override
  Widget build(BuildContext context) {
    return const SizedBox.shrink();
  }
}
