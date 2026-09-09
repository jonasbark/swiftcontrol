import 'dart:async';

import 'package:bike_control/bluetooth/devices/base_device.dart';
import 'package:bike_control/bluetooth/devices/proxy/proxy_device.dart';
import 'package:bike_control/bluetooth/devices/sensors/ble_sensor_device.dart';
import 'package:bike_control/gen/l10n.dart';
import 'package:bike_control/main.dart';
import 'package:bike_control/pages/proxy_device_details/metric_card.dart';
import 'package:bike_control/services/sensors/sensor_quantity.dart';
import 'package:bike_control/services/sensors/sensor_source.dart';
import 'package:bike_control/utils/core.dart';
import 'package:bike_control/utils/iap/iap_manager.dart';
import 'package:bike_control/utils/units.dart';
import 'package:flutter/foundation.dart';
import 'package:prop/emulators/definitions/proxy_bike_definition.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

/// The 2×2 live-metrics "signals grid" — POWER / HEART / CADENCE / SPEED —
/// and, per the Claude Design system spec, the app's ONE sensor surface: each
/// of the first three tiles grows an optional inline source control (see
/// `MetricSourceOption`) that both shows where the reading is coming from and
/// lets the rider pick a different one directly on the tile — no picker
/// sheet, no dropdown.
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
/// [_sourceOptionsFor] enforces this by returning null (no control at all)
/// whenever a quantity has no possible source besides the trainer. See
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
  /// standalone mode has to the source control — it must always render.
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
    // A source control's candidate list (registered + nearby sensors) and
    // "connecting" vs "connected" state can change independently of the
    // `ValueListenable`s the cards already bind to — e.g. a nearby strap
    // appearing makes an omitted control appear, and a fresh registration
    // flips "connecting" to "connected" without `droppedOut` ever changing
    // (it can already be false for both, per `SensorHub.select`'s not-found
    // branch). Mirrors the listener the deleted `SensorQuantitySelector` used
    // for the same reason.
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
    // the only route standalone mode has to the source control at all.
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
  /// this feature). Also renders the optional inline source control for this
  /// quantity.
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
              sources: _sourceOptionsFor(l10n, quantity, droppedOut),
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

  /// SPEED never gets a source control: no sensor in this codebase provides
  /// it (see `BleSensorSource`'s fixed set of characteristics), so a control
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

  /// [quantity]'s full source-list option set — Trainer first, then every
  /// sensor known to provide it, connected or not — or null to omit the
  /// control entirely: the tile-level invariant that a rider with no
  /// candidate sources at all (nothing registered, nothing nearby, nothing
  /// ever selected) must see no control, full stop. Once something HAS been
  /// selected the control stays, regardless of live candidate visibility, so
  /// the rider can always see what they picked and switch back to Trainer
  /// even if that sensor is currently out of range (the trailing "ghost"
  /// branch below).
  List<MetricSourceOption>? _sourceOptionsFor(AppLocalizations l10n, SensorQuantity quantity, bool droppedOut) {
    final selectedId = core.sensors.selectionFor(quantity);
    final candidates = _candidatesFor(quantity);
    if (selectedId == null && candidates.isEmpty) return null;

    final options = <MetricSourceOption>[
      MetricSourceOption(
        id: 'trainer',
        label: l10n.sensorSourceTrainer,
        subtitle: l10n.sensorSourceTrainerSubtitle,
        state: MetricSourceState.trainer,
        selected: selectedId == null,
        onSelect: () => _select(quantity, null),
      ),
    ];

    var selectionMatched = false;
    for (final candidate in candidates) {
      final isSelected = candidate.source.id == selectedId;
      if (isSelected) selectionMatched = true;
      final state = _candidateState(quantity, candidate, isSelected: isSelected, droppedOut: droppedOut);
      options.add(
        MetricSourceOption(
          id: candidate.source.id,
          label: candidate.source.displayName,
          subtitle: _candidateSubtitle(l10n, state, isSelected: isSelected),
          state: state,
          selected: isSelected,
          onSelect: () => _select(quantity, candidate),
          onDisconnect: isSelected && candidate.isConnected
              ? () => _disconnect(_connectedDeviceFor(candidate.source.id))
              : null,
        ),
      );
    }

    // A persisted selection whose sensor has neither registered nor come
    // back into BLE range: the one case with no real candidate to attach a
    // name or a live state to. Ported unchanged from the deleted single-row
    // version's identical fallback.
    if (selectedId != null && !selectionMatched) {
      options.add(
        MetricSourceOption(
          id: selectedId,
          label: l10n.sensorConnecting,
          subtitle: l10n.sensorSourceConnectingGhostSubtitle,
          state: MetricSourceState.connecting,
          selected: true,
          onSelect: () async {},
        ),
      );
    }

    return options;
  }

  /// The plain-English "what does this row mean" line under each source's
  /// own name — the point of the redesigned list per direct author feedback
  /// ("use subtitles ... to explain what each entry means"). Kept next to
  /// [_candidateState] since the two together fully describe a row: the
  /// dot's colour and this text must never disagree.
  ///
  /// [MetricSourceState.connected] is the one state real-world meaning
  /// splits in two depending on [isSelected] — see `_candidateState`'s doc
  /// comment on why a "connected" candidate can be either this quantity's
  /// live source or a sensor already linked for something else entirely.
  String _candidateSubtitle(AppLocalizations l10n, MetricSourceState state, {required bool isSelected}) {
    return switch (state) {
      MetricSourceState.trainer => l10n.sensorSourceTrainerSubtitle,
      MetricSourceState.notConnected => l10n.sensorSourceNotConnectedSubtitle,
      MetricSourceState.connecting => l10n.sensorConnecting,
      MetricSourceState.waitingForFirstReading => l10n.sensorAwaitingFirstReading,
      MetricSourceState.lost => l10n.sensorDroppedOut,
      MetricSourceState.connected =>
        isSelected ? l10n.sensorSourceConnectedSubtitle : l10n.sensorSourceConnectedElsewhereSubtitle,
    };
  }

  /// Every selectable, non-trainer source for [quantity]: already-registered
  /// ones (connected — see [_SourceCandidate]'s doc comment) from the hub,
  /// plus nearby [BleSensorDevice]s that provide it and are not registered
  /// yet. `registeredIds` also protects against listing an already-connected
  /// device twice for the brief window where it is both registered in the
  /// hub AND still present in `core.connection.devices`.
  List<_SourceCandidate> _candidatesFor(SensorQuantity quantity) {
    final registered = core.sensors.sourcesFor(quantity);
    final registeredIds = registered.map((s) => s.id).toSet();
    final nearby = core.connection.devices.whereType<BleSensorDevice>().where(
      (d) => d.source.provides.contains(quantity) && !registeredIds.contains(d.source.id),
    );
    return [
      for (final source in registered) _SourceCandidate(source),
      for (final device in nearby) _SourceCandidate(device.source, device: device),
    ];
  }

  /// A candidate's own dot state, independent of whether it happens to be
  /// [quantity]'s active selection:
  ///  - not registered: `notConnected` (never linked — tap to connect), or —
  ///    when it IS the active selection — `connecting` (a connect is in
  ///    flight, or a persisted pick is waiting for its sensor to come back
  ///    into range);
  ///  - registered: `connected`, per `SensorHub.register`'s own invariant
  ///    that a registered source is — by construction — currently linked,
  ///    UNLESS it is the active selection and the hub's per-quantity
  ///    freshness flag says otherwise, in which case `waitingForFirstReading`
  ///    / `lost` exactly as the deleted single-row version computed.
  MetricSourceState _candidateState(
    SensorQuantity quantity,
    _SourceCandidate candidate, {
    required bool isSelected,
    required bool droppedOut,
  }) {
    if (!candidate.isConnected) {
      return isSelected ? MetricSourceState.connecting : MetricSourceState.notConnected;
    }
    if (!isSelected || !droppedOut) return MetricSourceState.connected;
    final everReported = candidate.source.readingFor(quantity).value != null;
    return everReported ? MetricSourceState.lost : MetricSourceState.waitingForFirstReading;
  }

  BleSensorDevice? _connectedDeviceFor(String sourceId) {
    for (final device in core.connection.devices.whereType<BleSensorDevice>()) {
      if (device.source.id == sourceId) return device;
    }
    return null;
  }

  /// Picking an external source is a Pro feature — gated ahead of everything
  /// else, since selection has a real side effect on OTHER apps' pairings.
  ///
  /// CRITICAL — ordering ported unchanged from the deleted
  /// `SensorSourcePicker`/`SensorQuantitySelector`, and load-bearing: the
  /// per-device consent flag is persisted BEFORE `connectDevice` is ever
  /// called — `shouldAutoConnect` reads it and `connect()` early-returns
  /// otherwise (`BleHeartRateDevice.shouldAutoConnect`'s doc comment). Do not
  /// reorder.
  Future<void> _select(SensorQuantity quantity, _SourceCandidate? candidate) async {
    try {
      final sourceId = candidate?.source.id;
      if (sourceId != null && !IAPManager.instance.isProEnabledForCurrentDevice) {
        final granted = await IAPManager.instance.ensureProForFeature(
          context,
          featureName: _quantityTitle(AppLocalizations.of(context), quantity),
        );
        if (!granted) {
          // Nothing changed in the hub — force a rebuild so the control
          // snaps back to the hub's actual selection instead of lingering on
          // the tapped-but-rejected value.
          if (mounted) setState(() {});
          return;
        }
      }

      core.sensors.select(quantity, sourceId);
      // Persists every quantity's CURRENT selection, not just this one — see
      // `SensorHub.persistSelections`.
      await core.sensors.persistSelections(core.settings);

      final device = candidate?.device;
      if (device != null) {
        await core.settings.setSensorAutoConnect(device.device.deviceId, true);
        await core.connection.connectDevice(device);
      }
      if (mounted) setState(() {});
    } catch (e, s) {
      // Recorded here with a specific context AND rethrown: the enclosing
      // segment's `LoadingWidget` needs the exception too, to show its own
      // failure toast (see `_MetricSourceSegmentState.build`'s
      // `onErrorCallback`, metric_card.dart).
      await recordError(e, s, context: 'LiveMetricsSection._select');
      rethrow;
    }
  }

  /// The deliberate-forget case, not a transient drop — ordering ported
  /// unchanged from the deleted `SensorSourcePicker._disconnect`. The
  /// consent flag is cleared BEFORE calling `disconnect` so nothing can read
  /// a stale "yes" in the gap between the two calls; `forget: true` also
  /// drops any quantity selection pointing at this source
  /// (`Connection._unregisterSensorSource`), so the rider falls back to
  /// Trainer for it. `persistForget: false`, deliberately: this is "I'm done
  /// with my strap for now", not "this was never mine" — `true` would hide
  /// it from every future scan via the permanent ignore list.
  Future<void> _disconnect(BleSensorDevice? device) async {
    if (device == null) return;
    try {
      await core.settings.setSensorAutoConnect(device.device.deviceId, false);
      await core.connection.disconnect(device, forget: true, persistForget: false);
      if (mounted) setState(() {});
    } catch (e, s) {
      await recordError(e, s, context: 'LiveMetricsSection._disconnect');
      rethrow;
    }
  }
}

/// The tile's own quantity-scoped label, for the Pro-upgrade dialog's
/// `featureName` only. Kept local to this file rather than resurrecting the
/// deleted `SensorQuantitySelector`'s `SensorQuantityPresentation` extension:
/// nothing else in the surviving tree needs a title per [SensorQuantity] any
/// more.
String _quantityTitle(AppLocalizations l10n, SensorQuantity quantity) => switch (quantity) {
  SensorQuantity.heartRate => l10n.sensorQuantityHeartRate,
  SensorQuantity.cadence => l10n.sensorQuantityCadence,
  SensorQuantity.power => l10n.sensorQuantityPower,
  SensorQuantity.speed => l10n.sensorQuantitySpeed,
};

/// One selectable, non-trainer entry — ported unchanged from the deleted
/// `SensorSourcePicker._SourceCandidate`. [device] is non-null only while NOT
/// yet connected: a [source] already reachable through `SensorHub.sourcesFor`
/// is, by construction, currently connected (see `SensorHub.register`'s doc
/// comment), so there is nothing left for a tap to connect. A nearby sensor
/// that has never connected has no hub entry yet; [device] is what a tap on
/// it connects.
class _SourceCandidate {
  const _SourceCandidate(this.source, {this.device});

  final SensorSource source;
  final BleSensorDevice? device;

  bool get isConnected => device == null;
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
