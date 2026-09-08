import 'package:bike_control/gen/l10n.dart';
import 'package:bike_control/pages/sensors/sensor_quantity_selector.dart' show SensorQuantityPresentation;
import 'package:bike_control/services/sensors/sensor_hub.dart';
import 'package:bike_control/services/sensors/sensor_quantity.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

/// Quantities the grid can ever show a cell for. The same three
/// `SensorsSection` exposes a row for — speed has no real source behind it
/// yet (see that class's doc comment), so it is never a candidate here
/// either; adding it later is a one-line change to this list.
const List<SensorQuantity> _gridQuantities = [
  SensorQuantity.heartRate,
  SensorQuantity.cadence,
  SensorQuantity.power,
];

/// Whether [quantity] has a source that is both selected AND currently
/// connected. "Connected" here means registered in the hub — a source only
/// ever reaches [SensorHub.sourcesFor] once `Connection` has registered it,
/// which only happens once it is actually connected (see
/// `SensorHub.register`'s doc comment) — so this is deliberately NOT just
/// "has a selection": a selection pointing at a source that dropped out or
/// never registered yet must not draw an empty/stale cell.
bool _connectedAndSelected(SensorHub hub, SensorQuantity quantity) {
  final selectedId = hub.selectionFor(quantity);
  if (selectedId == null) return false;
  return hub.sourcesFor(quantity).any((source) => source.id == selectedId);
}

List<SensorQuantity> _gridEntries(SensorHub hub) => [
  for (final quantity in _gridQuantities)
    if (_connectedAndSelected(hub, quantity)) quantity,
];

/// Whether [TrainerCardSensorGrid] would render anything for [hub] right now.
///
/// Public rather than tucked inside the widget's own `build`: `home_page.dart`
/// needs the same answer to decide whether to reserve a gap for the grid,
/// without duplicating the check — and it makes the rider who has never
/// opened Sensors, for whom this is always false, testable directly: that is
/// THE invariant this feature must hold (see `_HomePageState._trainerBody`'s
/// doc comment).
bool sensorGridHasContent(SensorHub hub) => _gridEntries(hub).isNotEmpty;

/// The rider's connected, selected external sensors — heart rate, cadence,
/// power picked over the trainer's own on the Sensors page — as a compact
/// row of live readings on the home screen's Trainer card.
///
/// Renders nothing (`SizedBox.shrink`) when every quantity is still on the
/// trainer, which is what a rider who has never touched Sensors sees: this
/// widget adds nothing to the tree in that case beyond the shrink itself
/// (`_HomePageState._trainerBody` skips mounting it at all in that case, so
/// even that never actually happens in practice — see its doc comment).
///
/// Read-only by design: this card reports, it does not manage. Disconnecting
/// a sensor is a Sensors-page action (`SensorsSection`), reachable from Home
/// → extras → Sensors exactly as before — this grid is what was missing from
/// that round trip, not a replacement for it.
class TrainerCardSensorGrid extends StatelessWidget {
  const TrainerCardSensorGrid({super.key, required this.hub});

  final SensorHub hub;

  @override
  Widget build(BuildContext context) {
    final entries = _gridEntries(hub);
    if (entries.isEmpty) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);

    return Column(
      key: const Key('trainer-card-sensor-grid'),
      // Sized to its content, not the parent's offered height — the same
      // reason `DrivetrainControls._stacked` sets this. Left at the default
      // `MainAxisSize.max` this card sits fine inside the home page's own
      // scroll view, but a bare host (any test that isn't wrapped in one,
      // and there is no reason a future one always would be) can hand a
      // Column an unbounded height, and the Row below cannot tolerate that —
      // see its own comment.
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Same idiom as the home page's own Accessories caption: a quiet
        // label above a row of boxes, not a full section header — this is
        // context for the Trainer card, not a card of its own.
        Padding(
          padding: const EdgeInsets.fromLTRB(2, 0, 2, 6),
          child: Text(l10n.sensorsSectionTitle).xSmall.muted,
        ),
        Row(
          // NOT `.stretch`: a Row's cross axis is vertical, and stretching it
          // needs a bounded incoming height — inside a bare, non-scrolling
          // host that height is unbounded, and stretch-to-infinite-height is
          // a hard layout assertion, not a visual glitch. `Expanded` below
          // still splits the available WIDTH evenly (the Row's main axis),
          // untouched by this; every cell shares the same content shape, so
          // they end up the same height anyway without forcing it.
          spacing: 8,
          children: [for (final quantity in entries) Expanded(child: _cell(context, l10n, quantity))],
        ),
      ],
    );
  }

  Widget _cell(BuildContext context, AppLocalizations l10n, SensorQuantity quantity) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      key: Key('trainer-card-sensor-cell-${quantity.name}'),
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
      decoration: BoxDecoration(
        color: cs.muted,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: cs.border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        spacing: 4,
        children: [
          Icon(quantity.icon, size: 15, color: cs.mutedForeground),
          ValueListenableBuilder<int?>(
            valueListenable: hub.resolved(quantity),
            builder: (context, value, _) => Text(
              value != null ? quantity.formatValue(l10n, value) : l10n.sensorNoReadingYet,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                // The placeholder phrase is a full sentence, not a number — it
                // needs the smaller size to have any chance of fitting a cell
                // sized for "212 W".
                fontSize: value != null ? 17 : 10,
                fontWeight: FontWeight.w700,
                color: cs.foreground,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          Text(
            quantity.title(l10n),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: cs.mutedForeground),
          ),
        ],
      ),
    );
  }
}
