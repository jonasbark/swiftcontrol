import 'dart:ui' show lerpDouble;

import 'package:bike_control/gen/l10n.dart';
import 'package:flutter/widgets.dart' show BuildContext;
import 'package:prop/emulators/definitions/fitness_bike_definition.dart';

/// One of the four one-tap gearing presets offered in the gear-ratio editor.
///
/// Shared with the onboarding preview so the animated "tune your gearing"
/// scene cycles through the very presets a rider will find in the editor
/// afterwards, instead of a second, invented set that would drift out of sync.
class GearRatioPreset {
  final String label;
  final String range;
  final List<double> values;

  const GearRatioPreset({required this.label, required this.range, required this.values});
}

/// [count] ratios spread evenly between [lo] and [hi].
List<double> gearRatioEvenSteps(double lo, double hi, int count) =>
    List<double>.generate(count, (i) => lerpDouble(lo, hi, count == 1 ? 0.0 : i / (count - 1))!);

List<GearRatioPreset> gearRatioPresets(BuildContext context, int count) {
  final l10n = AppLocalizations.of(context);
  final defaults = FitnessBikeDefinition.defaultGearRatiosFor(count);
  return [
    GearRatioPreset(
      label: l10n.presetDefault,
      range: '0.75–5.49',
      // The stock curve is progressive rather than linear; the even-step
      // fallback only applies where no stock curve is available for the count.
      values: List<double>.unmodifiable(defaults.isNotEmpty ? defaults : gearRatioEvenSteps(0.75, 5.49, count)),
    ),
    GearRatioPreset(
      label: l10n.presetCompact,
      range: '1.00–4.00',
      values: List<double>.unmodifiable(gearRatioEvenSteps(1.00, 4.00, count)),
    ),
    GearRatioPreset(
      label: l10n.presetWide,
      range: '0.50–6.50',
      values: List<double>.unmodifiable(gearRatioEvenSteps(0.50, 6.50, count)),
    ),
    GearRatioPreset(
      label: l10n.preset1x,
      range: '2.20–4.20',
      values: List<double>.unmodifiable(gearRatioEvenSteps(2.20, 4.20, count)),
    ),
  ];
}
