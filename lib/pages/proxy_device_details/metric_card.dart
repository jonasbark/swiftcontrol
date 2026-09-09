import 'dart:async';

import 'package:bike_control/gen/l10n.dart';
import 'package:bike_control/widgets/ui/loading_widget.dart';
import 'package:bike_control/widgets/ui/small_progress_indicator.dart';
import 'package:bike_control/widgets/ui/toast.dart';
import 'package:prop/prop.dart' show LogLevel;
import 'package:shadcn_flutter/shadcn_flutter.dart';

/// The state a [MetricSourceOption]'s dot encodes.
///
/// Deliberately separate from any concept in `SensorHub`: the hub only knows
/// "resolved" and "dropped out", but a segment also has to tell "connecting"
/// (this quantity's selection, not yet registered — the BLE handshake is
/// still in flight, or a persisted pick waiting for its sensor to come back
/// into range) apart from "waiting for first reading" (registered, so the
/// link is up, there is just nothing on it yet) even though the hub reports
/// both as dropped-out. See `_candidateState` (live_metrics_section.dart)
/// for how each value is derived.
enum MetricSourceState {
  /// The trainer itself is the metric's source — the default, quiet state.
  /// Always shown on the Trainer segment, regardless of selection.
  trainer,

  /// A source that is registered in the hub — by construction, currently
  /// linked over BLE (see `SensorHub.register`'s doc comment) — whether or
  /// not it is this quantity's active selection.
  connected,

  /// This quantity's active selection, but not yet registered: a connect is
  /// in flight, or a persisted pick is waiting for its sensor to come back
  /// into range.
  connecting,

  /// This quantity's active selection, registered, but has never produced a
  /// reading.
  waitingForFirstReading,

  /// This quantity's active selection, registered, and has reported before,
  /// but its most recent reading is stale — the hub has fallen back to the
  /// trainer.
  lost,

  /// A known sensor that has never registered and is not this quantity's
  /// selection — nothing to read, tap to connect it.
  notConnected,
}

extension on MetricSourceState {
  /// Dot colours per the component spec. Deliberately NOT applied to a
  /// segment's text — see [MetricCard]'s doc comment on why the control has
  /// to stay muted regardless of state.
  Color dotColor(ColorScheme cs) => switch (this) {
    MetricSourceState.trainer => cs.mutedForeground,
    MetricSourceState.notConnected => cs.mutedForeground,
    MetricSourceState.connected => const Color(0xFF22C55E),
    MetricSourceState.connecting => const Color(0xFFF59E0B),
    MetricSourceState.waitingForFirstReading => const Color(0xFFF59E0B),
    MetricSourceState.lost => const Color(0xFFEF4444),
  };
}

/// One segment of a [MetricCard]'s inline source control — Trainer, or one
/// known sensor. Purely presentational — [MetricCard] renders exactly what
/// it is given; deciding WHICH options exist, in what order and what their
/// state is (`core.sensors` and `core.connection`) is
/// `live_metrics_section.dart`'s job.
class MetricSourceOption {
  const MetricSourceOption({
    required this.id,
    required this.label,
    required this.state,
    required this.selected,
    required this.onSelect,
    this.onDisconnect,
  });

  /// `'trainer'`, or the underlying sensor's `SensorSource.id` — this
  /// segment's [Key] suffix and its identity for the rider's current pick.
  final String id;

  /// The source's identity: "Trainer", or the sensor's own
  /// `SensorSource.displayName`. Always rendered in the same muted style
  /// regardless of [state] or [selected] — only the dot carries state, and
  /// only the pill background carries selection.
  final String label;

  final MetricSourceState state;

  /// Whether this is the quantity's current pick — drives the segment's
  /// `SelectedButton` pill.
  final bool selected;

  /// Tapping this segment. For Trainer this just clears the selection; for
  /// a not-yet-registered sensor, selecting IS the connect request — see
  /// `LiveMetricsSection._select`'s doc comment for the load-bearing
  /// ordering. Wrapped in a [LoadingWidget] so a real BLE connect shows a
  /// spinner in place of the label without this card needing to know that
  /// is happening.
  final Future<void> Function() onSelect;

  /// Long-press to disconnect. Only set on the selected, connected,
  /// non-Trainer segment — see [MetricCard]'s doc comment on why disconnect
  /// lives there rather than on every connected candidate or as a visible
  /// affordance.
  final Future<void> Function()? onDisconnect;
}

/// One tile of the live-metrics "signals grid" — POWER / HEART / CADENCE /
/// SPEED. The label and value rows are unchanged from before this feature: a
/// rider with no external sensors must see exactly this, pixel for pixel,
/// which is why [sources] defaults to null and — when null or empty — renders
/// nothing extra at all rather than an empty placeholder row.
///
/// The inline source control (when present) is deliberately muted: the
/// accent lives on the label row above, the value stays the hero in
/// foreground colour, and this control must never out-shout it. That is why
/// every segment's text stays [ColorScheme.mutedForeground] regardless of
/// [MetricSourceOption.selected] or state — only the dot carries state, and
/// only the pill's own (already-subtle) `ButtonStyle.secondary` background
/// carries selection.
class MetricCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final String? value; // null → "--"
  final String unit;

  /// Null or empty omits the control entirely — see this class's own doc
  /// comment on why that has to be the default.
  final List<MetricSourceOption>? sources;

  const MetricCard({
    super.key,
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.value,
    required this.unit,
    this.sources,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final options = sources;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: cs.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: cs.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 8,
          children: [
            Row(
              spacing: 6,
              children: [
                Icon(icon, size: 14, color: iconColor),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                    color: cs.mutedForeground,
                  ),
                ),
              ],
            ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              spacing: 4,
              children: [
                Text(
                  value ?? '--',
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.5,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    unit,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: cs.mutedForeground,
                    ),
                  ),
                ),
              ],
            ),
            if (options != null && options.isNotEmpty) _sourceControl(context, cs, options),
          ],
        ),
      ),
    );
  }

  /// A segmented list of every option, NOT a dropdown/picker — the rider
  /// picks a source directly on the tile. Wrapped in a horizontal
  /// [SingleChildScrollView] as a safety net for a quantity with many known
  /// sensors: each segment's label is already width-capped (see [_segment])
  /// so the common case (Trainer plus one or two sensors) never needs to
  /// scroll, but a longer list must still degrade to "scroll for the rest"
  /// rather than a hard layout overflow.
  Widget _sourceControl(BuildContext context, ColorScheme cs, List<MetricSourceOption> options) {
    return SizedBox(
      key: const Key('metric-card-source-control'),
      width: double.infinity,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: ButtonGroup(children: [for (final option in options) _segment(cs, option)]),
      ),
    );
  }

  /// One segment. shadcn_flutter has no `ToggleGroup` class at any version
  /// (checked against the installed 0.0.51 package source, and against
  /// 0.0.52/0.0.53 present in the local pub cache) — a `SelectedButton`
  /// inside a `ButtonGroup` is the primitive the package actually offers for
  /// this shape, and is what the rest of this app's toggle-style controls
  /// already use.
  Widget _segment(ColorScheme cs, MetricSourceOption option) {
    return _MetricSourceSegment(option: option, dotColor: option.state.dotColor(cs));
  }
}

/// One segment's own widget, rather than a bare method: disconnect (long
/// press) needs its own bracketed busy state, exactly like `LoadingWidget`
/// gives the tap/select path — a bare fire-and-forget `Future` here has
/// nothing that flips before the awaited work starts, so nothing signals
/// "still busy" to anything driving frames off it (`flutter_test`'s
/// `pumpAndSettle` included: with no state change until the very end, it
/// finds nothing scheduled and returns before the disconnect has actually
/// finished). Bracketing with [_disconnecting] fixes both that and gives the
/// rider the same busy affordance connecting already has.
class _MetricSourceSegment extends StatefulWidget {
  const _MetricSourceSegment({required this.option, required this.dotColor});

  final MetricSourceOption option;
  final Color dotColor;

  @override
  State<_MetricSourceSegment> createState() => _MetricSourceSegmentState();
}

class _MetricSourceSegmentState extends State<_MetricSourceSegment> {
  bool _disconnecting = false;

  Future<void> _runDisconnect() async {
    setState(() => _disconnecting = true);
    try {
      await widget.option.onDisconnect!();
    } finally {
      if (mounted) setState(() => _disconnecting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final option = widget.option;
    return LoadingWidget(
      futureCallback: option.onSelect,
      onErrorCallback: (context, error) =>
          buildToast(level: LogLevel.LOGLEVEL_WARNING, title: AppLocalizations.of(context).sensorConnectFailed),
      renderChild: (isLoading, tap) {
        final busy = isLoading || _disconnecting;
        return SelectedButton(
          key: Key('metric-card-source-option-${option.id}'),
          value: option.selected,
          enabled: !busy,
          onChanged: (_) => tap?.call(),
          onLongPressUp: option.onDisconnect == null || busy ? null : () => unawaited(_runDisconnect()),
          style: ButtonStyle.ghost().withPadding(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4)),
          selectedStyle: ButtonStyle.secondary().withPadding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            spacing: 4,
            children: [
              Container(
                key: Key('metric-card-source-dot-${option.id}'),
                width: 6,
                height: 6,
                decoration: BoxDecoration(shape: BoxShape.circle, color: widget.dotColor),
              ),
              // Capped so a long device name (e.g. "HR6 0050789") ellipsizes
              // instead of forcing this segment — and the scroll view it sits
              // in — wider than the tile has room for.
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 64),
                child: Text(
                  option.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: Theme.of(context).colorScheme.mutedForeground,
                  ),
                ),
              ),
              if (busy) const SmallProgressIndicator(),
            ],
          ),
        );
      },
    );
  }
}
