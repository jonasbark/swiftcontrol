import 'dart:async';

import 'package:bike_control/bluetooth/devices/base_device.dart';
import 'package:bike_control/bluetooth/devices/proxy/proxy_device.dart';
import 'package:bike_control/bluetooth/devices/sensors/ble_sensor_device.dart';
import 'package:bike_control/gen/l10n.dart';
import 'package:bike_control/pages/proxy_device_details/metric_card.dart';
import 'package:bike_control/pages/proxy_device_details/sensor_source_picker.dart';
import 'package:bike_control/services/sensors/sensor_quantity.dart';
import 'package:bike_control/services/sensors/sensor_source.dart';
import 'package:bike_control/utils/core.dart';
import 'package:bike_control/utils/units.dart';
import 'package:flutter/foundation.dart';
import 'package:prop/emulators/definitions/proxy_bike_definition.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

/// The 2×2 live-metrics "signals grid" — POWER / HEART / CADENCE / SPEED —
/// and, per the Claude Design system spec, the app's ONE sensor surface: each
/// of the first three tiles grows an optional source row (see
/// `MetricSourceRow`) that both shows where the reading is coming from and
/// opens the picker to change it (`openSensorSourcePicker`).
///
/// [device] is optional so this section also works in standalone mode — a
/// rider who has never bridged a trainer still needs somewhere to pick a
/// heart rate strap. When present, its own live telemetry is ONE input among
/// several: `core.sensors` (the external-sensor selection) always wins when
/// it resolves to a value, and the trainer is the fallback both when nothing
/// is selected and when a selection has gone stale — see `_quantityCard`.
///
/// A rider with no external sensors sees every tile render exactly as it did
/// before this feature existed: "--" and nothing else, no new affordance.
/// [_sourceRowFor] enforces this by returning null (no row at all) whenever a
/// quantity has no possible source besides the trainer. See
/// [hideWhenDeviceHasNoMetrics] for the one other pixel-fidelity case this
/// section has to preserve: a trainer present but not yet reporting anything.
class LiveMetricsSection extends StatefulWidget {
  final ProxyDevice? device;

  /// True on `ProxyDeviceDetailsPage`'s call site only — preserves this
  /// section's pre-existing behavior there exactly: a trainer that is
  /// present but has nothing to report yet (not connected, or connected
  /// without a parsed fitness definition) renders nothing at all, so a
  /// rider looking at THAT trainer's own page never sees a "--"-filled grid
  /// where there used to be nothing (see `build`).
  ///
  /// The home page's mount leaves this false: unlike a per-trainer page, it
  /// is reachable with no trainer bridged at all, so it is the only route
  /// standalone mode has to the source picker — it must always render.
  final bool hideWhenDeviceHasNoMetrics;

  const LiveMetricsSection({super.key, this.device, this.hideWhenDeviceHasNoMetrics = false});

  @override
  State<LiveMetricsSection> createState() => _LiveMetricsSectionState();
}

class _LiveMetricsSectionState extends State<LiveMetricsSection> {
  late StreamSubscription<BaseDevice> _connectionSub;

  @override
  void initState() {
    super.initState();
    // A source row's candidate list (registered + nearby sensors) and
    // "connecting" vs "connected" state can change independently of the
    // `ValueListenable`s the cards already bind to — e.g. a nearby strap
    // appearing makes an omitted row appear, and a fresh registration flips
    // "connecting" to "connected" without `droppedOut` ever changing (it can
    // already be false for both, per `SensorHub.select`'s not-found branch).
    // Mirrors the listener the deleted `SensorQuantitySelector` used for the
    // same reason.
    _connectionSub = core.connection.connectionStream.listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _connectionSub.cancel();
    super.dispose();
  }

  _LiveMetrics? _metrics() {
    final device = widget.device;
    if (device == null) return null;
    final proxyDef = device.emulator.composite.firstOfType<ProxyBikeDefinition>();
    if (proxyDef != null) {
      return _LiveMetrics(
        power: proxyDef.powerW,
        heartRate: proxyDef.heartRateBpm,
        cadence: proxyDef.cadenceRpm,
        speed: proxyDef.speedKph,
      );
    }
    final fitnessDef = device.fitnessBike;
    if (fitnessDef != null) {
      return _LiveMetrics(
        power: fitnessDef.powerW,
        heartRate: fitnessDef.heartRateBpm,
        cadence: fitnessDef.cadenceRpm,
        speed: fitnessDef.speedKph,
      );
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final device = widget.device;
    final metrics = _metrics();
    // A device that is present but has nothing to report (not yet connected,
    // or connected without a parsed fitness definition) renders nothing at
    // all — exactly what this section rendered before it knew about sensors,
    // for exactly this case. Only [device] being entirely absent (standalone
    // mode; impossible under the old, non-nullable signature) is new: THAT
    // case always renders the grid, "--" placeholders and all, since it is
    // the only route standalone mode has to the picker at all.
    if (device != null && metrics == null && widget.hideWhenDeviceHasNoMetrics) {
      return const SizedBox.shrink();
    }
    final l10n = AppLocalizations.of(context);
    final units = unitSystemOf(context);

    return Column(
      spacing: 10,
      children: [
        Row(
          spacing: 10,
          children: [
            _quantityCard(
              context: context,
              l10n: l10n,
              quantity: SensorQuantity.power,
              icon: LucideIcons.zap,
              iconColor: const Color(0xFFF59E0B),
              label: l10n.powerLabel,
              unit: 'W',
              trainerValue: metrics?.power,
            ),
            _quantityCard(
              context: context,
              l10n: l10n,
              quantity: SensorQuantity.heartRate,
              icon: LucideIcons.heart,
              iconColor: const Color(0xFFEF4444),
              label: l10n.heartLabel,
              unit: 'bpm',
              trainerValue: metrics?.heartRate,
            ),
          ],
        ),
        Row(
          spacing: 10,
          children: [
            _quantityCard(
              context: context,
              l10n: l10n,
              quantity: SensorQuantity.cadence,
              icon: LucideIcons.rotateCw,
              iconColor: const Color(0xFF8B5CF6),
              label: l10n.cadenceLabel,
              unit: 'rpm',
              trainerValue: metrics?.cadence,
            ),
            _speedCard(context, l10n, units, metrics?.speed),
          ],
        ),
      ],
    );
  }

  /// POWER / HEART / CADENCE: value is the external-sensor selection when it
  /// resolves, else this trainer's own reading (present-but-no-device and
  /// no-selection both collapse to null, i.e. "--" — unchanged from before
  /// this feature). Also renders the optional source row for this quantity.
  Widget _quantityCard({
    required BuildContext context,
    required AppLocalizations l10n,
    required SensorQuantity quantity,
    required IconData icon,
    required Color iconColor,
    required String label,
    required String unit,
    required ValueListenable<int?>? trainerValue,
  }) {
    return ValueListenableBuilder<int?>(
      valueListenable: core.sensors.resolved(quantity),
      builder: (context, external, _) {
        Widget withDeviceValue(int? deviceReading) {
          final value = external ?? deviceReading;
          return ValueListenableBuilder<bool>(
            valueListenable: core.sensors.droppedOut(quantity),
            builder: (context, droppedOut, _) => MetricCard(
              key: Key('metric-card-${quantity.name}'),
              icon: icon,
              iconColor: iconColor,
              label: label,
              value: value?.toString(),
              unit: unit,
              source: _sourceRowFor(context, l10n, quantity, droppedOut),
            ),
          );
        }

        if (trainerValue == null) return withDeviceValue(null);
        return ValueListenableBuilder<int?>(
          valueListenable: trainerValue,
          builder: (context, deviceReading, _) => withDeviceValue(deviceReading),
        );
      },
    );
  }

  /// SPEED never gets a source row: no sensor in this codebase provides it
  /// (see `BleSensorSource`'s fixed set of characteristics), so a control
  /// that could only ever say "Trainer" would be noise. Reads straight off
  /// the trainer, exactly as before this feature.
  Widget _speedCard(BuildContext context, AppLocalizations l10n, UnitSystem units, ValueListenable<double?>? speed) {
    if (speed == null) {
      return MetricCard(
        key: const Key('metric-card-speed'),
        icon: LucideIcons.gauge,
        iconColor: const Color(0xFF0EA5E9),
        label: l10n.speedLabel,
        value: null,
        unit: units.speedSymbol,
      );
    }
    return ValueListenableBuilder<double?>(
      valueListenable: speed,
      builder: (context, v, _) => MetricCard(
        key: const Key('metric-card-speed'),
        icon: LucideIcons.gauge,
        iconColor: const Color(0xFF0EA5E9),
        label: l10n.speedLabel,
        value: v == null ? null : units.fromKph(v).toStringAsFixed(1),
        unit: units.speedSymbol,
      ),
    );
  }

  /// The row's state/label for [quantity], or null to omit it entirely — the
  /// tile-level invariant: a rider with no candidate sources at all (nothing
  /// registered, nothing nearby, nothing ever selected) must see no row,
  /// full stop. Once something HAS been selected the row stays, regardless
  /// of live candidate visibility, so the rider can always see what they
  /// picked and switch back to Trainer even if that sensor is currently out
  /// of range.
  MetricSourceRow? _sourceRowFor(BuildContext context, AppLocalizations l10n, SensorQuantity quantity, bool droppedOut) {
    final hub = core.sensors;
    final selectedId = hub.selectionFor(quantity);
    final registered = hub.sourcesFor(quantity);
    void onTap() => openSensorSourcePicker(context, quantity: quantity);

    if (selectedId == null) {
      final registeredIds = registered.map((s) => s.id).toSet();
      final hasNearby = core.connection.devices
          .whereType<BleSensorDevice>()
          .any((d) => d.source.provides.contains(quantity) && !registeredIds.contains(d.source.id));
      if (registered.isEmpty && !hasNearby) return null;
      return MetricSourceRow(state: MetricSourceState.trainer, label: l10n.sensorSourceTrainer, onTap: onTap);
    }

    SensorSource? selected;
    for (final source in registered) {
      if (source.id == selectedId) {
        selected = source;
        break;
      }
    }
    if (selected == null) {
      return MetricSourceRow(state: MetricSourceState.connecting, label: l10n.sensorConnecting, onTap: onTap);
    }
    if (!droppedOut) {
      return MetricSourceRow(state: MetricSourceState.connected, label: selected.displayName, onTap: onTap);
    }
    final everReported = selected.readingFor(quantity).value != null;
    if (!everReported) {
      return MetricSourceRow(
        state: MetricSourceState.waitingForFirstReading,
        label: l10n.sensorAwaitingFirstReading,
        onTap: onTap,
      );
    }
    return MetricSourceRow(state: MetricSourceState.lost, label: l10n.sensorDroppedOut, onTap: onTap);
  }
}

class _LiveMetrics {
  final ValueListenable<int?> power;
  final ValueListenable<int?> heartRate;
  final ValueListenable<int?> cadence;
  final ValueListenable<double?> speed;

  const _LiveMetrics({
    required this.power,
    required this.heartRate,
    required this.cadence,
    required this.speed,
  });
}
