import 'package:shadcn_flutter/shadcn_flutter.dart';

/// The state a [MetricCard]'s source row's leading dot encodes.
///
/// Deliberately separate from any concept in `SensorHub`: the hub only knows
/// "resolved" and "dropped out", but the row also has to tell "connecting"
/// (selected, not yet registered — the BLE handshake is still in flight)
/// apart from "waiting for first reading" (registered, so the link is up,
/// there is just nothing on it yet) even though the hub reports both as
/// dropped-out. See `sourceRowFor` (live_metrics_section.dart) for how each
/// value is derived.
enum MetricSourceState {
  /// The trainer itself is the metric's source — the default, quiet state.
  trainer,

  /// An external sensor is selected, registered, and fresh.
  connected,

  /// An external sensor is selected but not yet registered in the hub.
  connecting,

  /// An external sensor is selected and registered, but has never produced a
  /// reading.
  waitingForFirstReading,

  /// An external sensor was selected and has reported before, but its most
  /// recent reading is stale — the hub has fallen back to the trainer.
  lost,
}

extension on MetricSourceState {
  /// Dot colours per the component spec. Deliberately NOT applied to the
  /// row's text — see [MetricSourceRow]'s doc comment.
  Color dotColor(ColorScheme cs) => switch (this) {
    MetricSourceState.trainer => cs.mutedForeground,
    MetricSourceState.connected => const Color(0xFF22C55E),
    MetricSourceState.connecting => const Color(0xFFF59E0B),
    MetricSourceState.waitingForFirstReading => const Color(0xFFF59E0B),
    MetricSourceState.lost => const Color(0xFFEF4444),
  };
}

/// The optional row a [MetricCard] grows below its value. Purely
/// presentational — [MetricCard] renders exactly what it is given; deciding
/// WHETHER a quantity gets a row at all (and what its state/label are) is
/// `live_metrics_section.dart`'s job, since that is where `core.sensors` and
/// `core.connection` live.
class MetricSourceRow {
  const MetricSourceRow({required this.state, required this.label, required this.onTap});

  final MetricSourceState state;

  /// The source's identity: "Trainer", or the selected sensor's own
  /// `SensorSource.displayName`. Always rendered in the same muted style
  /// regardless of [state] — only the dot changes colour, per the spec's
  /// "accent on the label row only; the number stays foreground" rule
  /// extended to this row: the row itself must never compete with the
  /// number above it.
  final String label;

  final VoidCallback onTap;
}

/// One tile of the live-metrics "signals grid" — POWER / HEART / CADENCE /
/// SPEED. The label and value rows are unchanged from before this feature: a
/// rider with no external sensors must see exactly this, pixel for pixel,
/// which is why [source] defaults to null and — when null — renders nothing
/// extra at all rather than an empty placeholder row.
class MetricCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final String? value; // null → "--"
  final String unit;

  /// Null omits the row entirely — see [MetricSourceRow]'s doc comment and
  /// this class's own doc comment on why that has to be the default.
  final MetricSourceRow? source;

  const MetricCard({
    super.key,
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.value,
    required this.unit,
    this.source,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
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
            if (source != null) _sourceRow(context, cs, source!),
          ],
        ),
      ),
    );
  }

  Widget _sourceRow(BuildContext context, ColorScheme cs, MetricSourceRow source) {
    return Button.ghost(
      key: const Key('metric-card-source-row'),
      style: ButtonStyle.ghost().withPadding(padding: EdgeInsets.zero),
      onPressed: source.onTap,
      child: Row(
        spacing: 6,
        children: [
          Container(
            key: const Key('metric-card-source-dot'),
            width: 6,
            height: 6,
            decoration: BoxDecoration(shape: BoxShape.circle, color: source.state.dotColor(cs)),
          ),
          Expanded(
            child: Text(
              source.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: cs.mutedForeground),
            ),
          ),
          Icon(LucideIcons.chevronDown, size: 12, color: cs.mutedForeground),
        ],
      ),
    );
  }
}
