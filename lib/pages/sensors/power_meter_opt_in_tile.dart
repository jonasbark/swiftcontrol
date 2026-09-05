import 'package:bike_control/gen/l10n.dart';
import 'package:bike_control/main.dart' show recordError;
import 'package:bike_control/utils/core.dart';
import 'package:bike_control/widgets/ui/setting_tile.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

/// Lets the rider opt in to detecting power meters that are hidden from
/// scans by default.
///
/// `BluetoothDevice.fromScanResult` hides a short, known list of power-meter
/// names (Favero Assioma, Quarq, PowerCrank, ...) unless
/// `Settings.getPowerMeterOptIn()` is true — see that method's doc comment.
/// The reason is a real tradeoff, not caution for its own sake: many power
/// meters accept only one simultaneous Bluetooth connection, so pairing one
/// to BikeControl can silently take it away from a rider's bike computer or
/// head unit mid-ride. This tile puts that tradeoff in front of the rider —
/// see `sensorPowerMeterOptInSubtitle` — rather than exposing a bare switch
/// with no explanation.
class PowerMeterOptInTile extends StatefulWidget {
  const PowerMeterOptInTile({super.key});

  @override
  State<PowerMeterOptInTile> createState() => _PowerMeterOptInTileState();
}

class _PowerMeterOptInTileState extends State<PowerMeterOptInTile> {
  Future<void> _toggle(bool value) async {
    try {
      await core.settings.setPowerMeterOptIn(value);
      if (mounted) setState(() {});
    } catch (e, s) {
      await recordError(e, s, context: 'PowerMeterOptInTile._toggle');
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SettingTile(
      key: const Key('power-meter-opt-in-tile'),
      icon: LucideIcons.radar,
      title: l10n.sensorPowerMeterOptInTitle,
      subtitle: l10n.sensorPowerMeterOptInSubtitle,
      trailing: Switch(
        key: const Key('power-meter-opt-in-switch'),
        value: core.settings.getPowerMeterOptIn(),
        onChanged: _toggle,
      ),
    );
  }
}
