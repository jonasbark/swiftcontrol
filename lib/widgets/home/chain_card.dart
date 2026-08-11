import 'package:bike_control/pages/home/chain_state.dart';
import 'package:bike_control/utils/i18n_extension.dart';
import 'package:bike_control/widgets/home/ampel.dart';
import 'package:bike_control/widgets/home/chain_labels.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

/// One link of the setup chain.
///
/// Every card in the chain has the same three parts, so the rider learns the
/// shape once: an Ampel that says how this link is doing, an `Edit` in the same
/// place on every card, and a tick-off checklist whose next action carries its
/// own instructions. Instructions sit next to the thing they are about — the
/// rider never leaves the card to find out what is missing.
class ChainCard extends StatefulWidget {
  const ChainCard({
    super.key,
    required this.link,
    required this.tile,
    required this.title,
    required this.statusLabel,
    this.appName,
    this.editLabel,
    this.onEdit,
    this.onInstructions,
    this.instructionsLabel,
    this.body,
  });

  final ChainLink link;

  /// The card's visual identity — a device icon or the trainer app's logo.
  final Widget tile;

  final String title;
  final String statusLabel;

  /// Used to fill "{app} is connected" style step wording.
  final String? appName;

  final String? editLabel;
  final VoidCallback? onEdit;

  /// Opens the guide for the active step. Only the active step offers it, so
  /// there is exactly one next action visible per card.
  final VoidCallback? onInstructions;
  final String? instructionsLabel;

  /// Extra content between the header and the checklist — the controller
  /// contour, for instance.
  final Widget? body;

  @override
  State<ChainCard> createState() => _ChainCardState();
}

/// Long enough to read as a movement, short enough not to hold the rider up.
const Duration _statusChangeDuration = Duration(milliseconds: 260);

/// One left edge for everything in a card's checklist region — the summary
/// row's icon and every step's tick share it, so the column reads as a column.
/// The leading glyphs differ in size (a 15px icon, a 17px circle), so they are
/// centred in a box of one width rather than laid out back to back, which is
/// what let them drift apart.
const double _rowInset = 14;

/// The tick circle, so a test can assert it lines up with the summary icon
/// above it — the alignment is the point of the shared inset.
const Key stepTickKey = ValueKey('chain-step-tick');

const double _leadingSize = 17;
const double _leadingGap = 10;

class _ChainCardState extends State<ChainCard> {
  /// Null means "follow the link's own default" — ready cards collapse,
  /// unresolved cards open. Once the rider taps the summary row, their choice
  /// wins until the card's status changes under them.
  bool? _expandedOverride;

  LinkStatus? _lastStatus;

  bool get _expanded => _expandedOverride ?? widget.link.startsExpanded;

  @override
  void didUpdateWidget(covariant ChainCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A status change is new information — it re-earns the right to decide
    // whether the checklist is open, so a card that just broke opens itself
    // even if the rider had collapsed it earlier.
    if (_lastStatus != null && widget.link.status != _lastStatus) {
      _expandedOverride = null;
    }
    _lastStatus = widget.link.status;
  }

  @override
  void initState() {
    super.initState();
    _lastStatus = widget.link.status;
  }

  @override
  Widget build(BuildContext context) {
    final link = widget.link;
    final theme = Theme.of(context);
    final dimmed = link.optional && link.status == LinkStatus.off;
    final border = BorderSide(
      color: dimmed ? theme.colorScheme.mutedForeground.withAlpha(90) : theme.colorScheme.border,
      width: 1.5,
    );

    return AnimatedContainer(
      duration: _statusChangeDuration,
      curve: Curves.easeOut,
      decoration: ShapeDecoration(
        color: theme.colorScheme.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          // A dashed border isn't available here, so an optional card at rest is
          // marked by a faded border plus the OPTIONAL tag instead.
          side: border,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _header(context),
          if (widget.body != null) Padding(padding: const EdgeInsets.fromLTRB(12, 0, 12, 12), child: widget.body!),
          // The checklist grows and shrinks rather than blinking in and out: when
          // the last step of a card finally ticks, the card collapses to its
          // one-line summary as a movement the eye can follow, which is what
          // makes "that's done now" legible instead of just sudden.
          AnimatedSize(
            duration: _statusChangeDuration,
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: link.steps.isEmpty
                ? const SizedBox(width: double.infinity)
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _summaryRow(context),
                      if (_expanded) _checklist(context),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _header(BuildContext context) {
    final link = widget.link;
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(13, 13, 6, 13),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          TileWithAmpel(status: link.status, child: widget.tile),
          const Gap(12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        widget.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700),
                      ),
                    ),
                    if (link.optional) ...[
                      const Gap(7),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.muted,
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: Text(
                          context.i18n.chainOptional.toUpperCase(),
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.4,
                            color: theme.colorScheme.mutedForeground,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                StatusLine(status: link.status, label: widget.statusLabel, meta: link.subtitleArg),
              ],
            ),
          ),
          if (widget.onEdit != null)
            Button.ghost(
              onPressed: widget.onEdit,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.editLabel ?? context.i18n.chainEdit,
                    style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: theme.colorScheme.primary),
                  ),
                  Icon(LucideIcons.chevronRight, size: 15, color: theme.colorScheme.primary),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// The one-line summary. On a ready card this is the *entire* checklist the
  /// rider sees — "All 3 steps done" and nothing else.
  Widget _summaryRow(BuildContext context) {
    final link = widget.link;
    final theme = Theme.of(context);
    final ready = link.status == LinkStatus.ready;

    return Button.ghost(
      // The button's own padding would inset this row past the steps below it.
      style: ButtonStyle.ghost().withPadding(padding: EdgeInsets.zero),
      onPressed: () => setState(() => _expandedOverride = !_expanded),
      child: Container(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: theme.colorScheme.border, width: 0.5)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: _rowInset, vertical: 12),
        child: Row(
          children: [
            SizedBox(
              width: _leadingSize,
              child: Icon(
                ready ? LucideIcons.circleCheck : LucideIcons.listChecks,
                size: 15,
                color: theme.colorScheme.mutedForeground,
              ),
            ),
            const Gap(_leadingGap),
            Expanded(
              child: Text(
                ready
                    ? context.i18n.chainAllStepsDone(link.steps.length)
                    : context.i18n.chainStepsDone(link.doneSteps, link.steps.length),
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.mutedForeground,
                ),
              ),
            ),
            Icon(
              _expanded ? LucideIcons.chevronUp : LucideIcons.chevronDown,
              size: 15,
              color: theme.colorScheme.mutedForeground,
            ),
          ],
        ),
      ),
    );
  }

  Widget _checklist(BuildContext context) {
    final link = widget.link;
    final activeIndex = link.activeStepIndex;

    return Padding(
      // Steps carry their own inset (see StepRow) so the active step's
      // highlight can bleed slightly wider than the text column.
      padding: const EdgeInsets.fromLTRB(4, 2, 4, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (index, step) in link.steps.indexed)
            StepRow(
              step: step,
              active: index == activeIndex,
              appName: widget.appName,
              onInstructions: index == activeIndex ? widget.onInstructions : null,
              instructionsLabel: widget.instructionsLabel,
            ),
        ],
      ),
    );
  }
}

/// A single checklist line. The first unfinished step is the "active" one and
/// is the only place an instructions button appears — so there is exactly one
/// next action on the card.
class StepRow extends StatelessWidget {
  const StepRow({
    super.key,
    required this.step,
    required this.active,
    this.appName,
    this.onInstructions,
    this.instructionsLabel,
  });

  final SetupStep step;
  final bool active;
  final String? appName;
  final VoidCallback? onInstructions;
  final String? instructionsLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = chainStepText(context, step, appName: appName);
    final success = AmpelStyle.of(context, LinkStatus.ready).color;
    final tone = step.done
        ? success
        : active
        ? theme.colorScheme.primary
        : theme.colorScheme.mutedForeground.withAlpha(120);
    final hint = text.hint;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      margin: const EdgeInsets.only(bottom: 2),
      padding: EdgeInsets.symmetric(horizontal: _rowInset - 4, vertical: active ? 9 : 7),
      decoration: BoxDecoration(
        color: active ? theme.colorScheme.primary.withAlpha(15) : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Container(
              key: stepTickKey,
              width: _leadingSize,
              height: _leadingSize,
              decoration: BoxDecoration(
                color: step.done ? success : Colors.transparent,
                shape: BoxShape.circle,
                border: step.done ? null : Border.all(color: tone, width: 2),
              ),
              child: step.done ? const Icon(LucideIcons.check, size: 11, color: Colors.white) : null,
            ),
          ),
          const Gap(_leadingGap),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  text.label,
                  style: TextStyle(
                    fontSize: 13.5,
                    height: 1.35,
                    fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                    color: step.done ? theme.colorScheme.mutedForeground : theme.colorScheme.foreground,
                  ),
                ),
                // A hint on a finished step is only worth the space when it says
                // something the label doesn't — the gear summary, for instance.
                if (hint != null && hint.isNotEmpty && (active || !step.done || step.hintArg != null)) ...[
                  const Gap(3),
                  Text(
                    hint,
                    style: TextStyle(fontSize: 12, height: 1.4, color: theme.colorScheme.mutedForeground),
                  ),
                ],
                if (active && onInstructions != null) ...[
                  const Gap(8),
                  PrimaryButton(
                    size: ButtonSize.small,
                    onPressed: onInstructions,
                    leading: const Icon(LucideIcons.bookOpen, size: 13),
                    child: Text(instructionsLabel ?? context.i18n.chainShowMeHow),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
