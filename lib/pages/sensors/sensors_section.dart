import 'dart:async';

import 'package:bike_control/bluetooth/devices/base_device.dart';
import 'package:bike_control/bluetooth/devices/sensors/ble_sensor_device.dart';
import 'package:bike_control/gen/l10n.dart';
import 'package:bike_control/pages/sensors/sensor_quantity_selector.dart';
import 'package:bike_control/services/sensors/sensor_hub.dart';
import 'package:bike_control/services/sensors/sensor_quantity.dart';
import 'package:bike_control/utils/core.dart';
import 'package:bike_control/widgets/ui/loading_widget.dart';
import 'package:bike_control/widgets/ui/small_progress_indicator.dart';
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
///
/// Below the quantity rows, [_ConnectedSensorsSection] lists whatever
/// BikeControl is currently holding a BLE connection open to, with a way to
/// disconnect it — selecting a source is reachable from the rows above, but
/// before this existed there was no way back out of that choice at all.
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
        _ConnectedSensorsSection(hub: hub),
      ],
    );
  }
}

/// Every currently-connected sensor, with a way to disconnect it — the gap
/// the author's feedback called out directly: "You can't even disconnect a
/// sensor there." The quantity rows above answer "where does this reading
/// come from"; this answers "what is BikeControl holding a BLE connection
/// open to right now", which can include a device that no quantity happens
/// to have selected (a rider can connect a sensor for cadence and leave power
/// on the trainer even though the same meter offers both).
///
/// A device is "connected" here exactly when its source is registered in
/// [hub] — the same notion `SensorQuantitySelector._SourceCandidate` uses
/// (see its doc comment) — cross-referenced against `core.connection.devices`
/// to get back the actual [BleSensorDevice] a disconnect call needs a target
/// object for; [SensorSource] itself is transport-agnostic and holds no
/// device reference.
class _ConnectedSensorsSection extends StatefulWidget {
  const _ConnectedSensorsSection({required this.hub});

  final SensorHub hub;

  @override
  State<_ConnectedSensorsSection> createState() => _ConnectedSensorsSectionState();
}

class _ConnectedSensorsSectionState extends State<_ConnectedSensorsSection> {
  late StreamSubscription<BaseDevice> _connectionSub;

  @override
  void initState() {
    super.initState();
    // Same reason `SensorQuantitySelector` listens to this stream: a
    // disconnect (or a fresh connect elsewhere) must drop or add a row here
    // live, without the rider leaving and reopening this page.
    _connectionSub = core.connection.connectionStream.listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _connectionSub.cancel();
    super.dispose();
  }

  List<BleSensorDevice> _connectedDevices() {
    final connectedIds = widget.hub.sources.map((source) => source.id).toSet();
    return core.connection.devices
        .whereType<BleSensorDevice>()
        .where((device) => connectedIds.contains(device.source.id))
        .toList();
  }

  /// The deliberate-forget case, not a transient drop (see
  /// `Connection.disconnect`'s own doc comment on that distinction): the
  /// rider tapped Disconnect on THIS device, on the very page that lets them
  /// pick it again, so this has to behave like a considered decision, not a
  /// dropped signal.
  ///
  /// The consent flag is cleared BEFORE calling `disconnect` — the same
  /// load-bearing ordering `SensorQuantitySelector._select` uses in reverse
  /// (set the flag, THEN connect) — so nothing can read a stale "yes" in the
  /// gap between the two calls. Without it, `shouldAutoConnect` stays true
  /// and the very next scan reconnects the sensor right back
  /// (`BleHeartRateDevice.shouldAutoConnect`'s doc comment).
  ///
  /// `forget: true` is also what makes `Connection` drop any quantity
  /// selection pointing at this source
  /// (`Connection._unregisterSensorSource`), so the rider falls back to
  /// Trainer for it rather than being left selected-but-absent.
  ///
  /// `persistForget: false`, deliberately: `true` would add the device to
  /// the permanent ignore list (`Settings.addIgnoredDevice`), which also
  /// hides it from every future scan — it would never be offered as a
  /// reconnectable candidate on this same page again, and undoing that means
  /// finding the separate Ignored Devices dialog. That is the right answer
  /// for a device that was never the rider's; it is the wrong one for "I'm
  /// done with my strap for now" — the ordinary meaning of Disconnect here,
  /// and exactly what `persistForget: false` already means for a controller's
  /// own "Disconnect" action (`controller_settings.dart`).
  ///
  /// No try/catch here: wrapped in [LoadingWidget] below, whose
  /// `futureCallback` already forwards any failure through `recordError`
  /// before toasting it — the exact mechanism `_SensorToggle` relies on for
  /// its own connect attempts.
  Future<void> _disconnect(BleSensorDevice device) async {
    await core.settings.setSensorAutoConnect(device.device.deviceId, false);
    await core.connection.disconnect(device, forget: true, persistForget: false);
  }

  @override
  Widget build(BuildContext context) {
    final devices = _connectedDevices();
    if (devices.isEmpty) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 8,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(2, 4, 2, 0),
          child: Text(l10n.sensorsConnectedSectionTitle).xSmall.muted,
        ),
        for (final device in devices) _row(context, l10n, device),
      ],
    );
  }

  Widget _row(BuildContext context, AppLocalizations l10n, BleSensorDevice device) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      key: Key('sensor-connected-${device.source.id}'),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(color: cs.muted, borderRadius: BorderRadius.circular(10)),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              spacing: 2,
              children: [
                Text(device.source.displayName, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                Text(_kindLabel(l10n, device.source.provides), style: TextStyle(fontSize: 11, color: cs.mutedForeground)),
              ],
            ),
          ),
          LoadingWidget(
            futureCallback: () => _disconnect(device),
            renderChild: (isLoading, tap) => Button.ghost(
              key: Key('sensor-disconnect-${device.source.id}'),
              enabled: !isLoading,
              onPressed: tap,
              child: isLoading
                  ? const SmallProgressIndicator()
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      spacing: 4,
                      children: [
                        Icon(LucideIcons.bluetoothOff, size: 14, color: cs.destructive),
                        Text(
                          l10n.disconnectAndForgetForThisSession,
                          style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: cs.destructive),
                        ),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Kind label for a connected sensor's [SensorSource.provides] set. Mirrors
/// `_sensorKindLabel` in `sensor_quantity_selector.dart` — same priority
/// (power before cadence, since a power meter's source always provides both;
/// see that function's doc comment) — kept as its own small copy rather than
/// exported from that file, so this section's "what is connected" list stays
/// independent of the toggle group's private rendering details.
String _kindLabel(AppLocalizations l10n, Set<SensorQuantity> provides) {
  if (provides.contains(SensorQuantity.power)) return l10n.sensorKindPowerMeter;
  if (provides.contains(SensorQuantity.cadence)) return l10n.sensorKindCadenceSensor;
  return l10n.sensorKindHeartRateMonitor;
}
