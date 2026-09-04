import 'package:bike_control/gen/l10n.dart';
import 'package:bike_control/pages/sensors/sensor_quantity_selector.dart';
import 'package:bike_control/services/sensors/sensor_hub.dart';
import 'package:bike_control/services/sensors/sensor_quantity.dart';
import 'package:bike_control/services/sensors/sensor_source.dart';
import 'package:bike_control/widgets/ui/setting_tile.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

/// Lets the rider see every registered external sensor and choose, per
/// metric, whether BikeControl should use it instead of the trainer's own
/// reading.
///
/// Only heart rate is wired to a real source today (a BLE chest strap) —
/// cadence, power and speed are a later phase (external CSC/power parsing,
/// then HealthKit; see the spec's follow-on plans). Showing selectors for
/// them now would offer a control that can only ever resolve to "Trainer",
/// so this section deliberately renders just the heart-rate row. The
/// underlying `SensorQuantitySelector` is written generically, so adding the
/// other three rows later is a one-line change here, not new widget work.
class SensorsSection extends StatelessWidget {
  final SensorHub hub;

  const SensorsSection({super.key, required this.hub});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 10,
      children: [
        Text(
          l10n.sensorsSectionTitle,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600, letterSpacing: -0.2),
        ),
        _pairedSources(context, l10n),
        SensorQuantitySelector(hub: hub, quantity: SensorQuantity.heartRate),
      ],
    );
  }

  Widget _pairedSources(BuildContext context, AppLocalizations l10n) {
    if (hub.sources.isEmpty) {
      final cs = Theme.of(context).colorScheme;
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: cs.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: cs.border),
        ),
        child: Text(
          l10n.sensorsNoPairedSources,
          style: TextStyle(fontSize: 13, color: cs.mutedForeground),
        ),
      );
    }
    return Column(
      spacing: 8,
      children: [for (final source in hub.sources) _sourceRow(l10n, source)],
    );
  }

  Widget _sourceRow(AppLocalizations l10n, SensorSource source) {
    return SettingTile(
      icon: LucideIcons.radio,
      title: source.displayName,
      subtitle: source.provides.map((q) => q.title(l10n)).join(', '),
    );
  }
}
