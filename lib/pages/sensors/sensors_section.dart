import 'package:bike_control/gen/l10n.dart';
import 'package:bike_control/pages/sensors/sensor_quantity_selector.dart';
import 'package:bike_control/services/sensors/sensor_hub.dart';
import 'package:bike_control/services/sensors/sensor_quantity.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

/// Quantity-first: each rider metric that has a real external source behind
/// it — Heart Rate, Cadence, Power — gets its own row (`SensorQuantitySelector`)
/// listing every selectable source for THAT metric: the trainer, then every
/// known sensor that provides it, connected or not. There is no separate
/// device-first "paired sources" or "nearby sensors" list any more — a
/// sensor now surfaces inside every quantity row it serves, which is also
/// how the rider connects one in the first place (see
/// `SensorQuantitySelector._select`).
///
/// Speed does not yet have a real source behind it (see the spec's follow-on
/// plans), so it stays hidden rather than offering a control that can only
/// ever resolve to "Trainer". `SensorQuantitySelector` is written generically
/// over `SensorQuantity`, so adding that fourth row later is a one-line
/// change here, not new widget work.
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
        SensorQuantitySelector(
          key: const Key('sensor-quantity-heartRate'),
          hub: hub,
          quantity: SensorQuantity.heartRate,
        ),
        SensorQuantitySelector(
          key: const Key('sensor-quantity-cadence'),
          hub: hub,
          quantity: SensorQuantity.cadence,
        ),
        SensorQuantitySelector(
          key: const Key('sensor-quantity-power'),
          hub: hub,
          quantity: SensorQuantity.power,
        ),
      ],
    );
  }
}
