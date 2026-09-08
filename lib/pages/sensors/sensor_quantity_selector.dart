import 'dart:async';

import 'package:bike_control/bluetooth/devices/base_device.dart';
import 'package:bike_control/bluetooth/devices/sensors/ble_sensor_device.dart';
import 'package:bike_control/gen/l10n.dart';
import 'package:bike_control/main.dart';
import 'package:bike_control/services/sensors/sensor_hub.dart';
import 'package:bike_control/services/sensors/sensor_quantity.dart';
import 'package:bike_control/services/sensors/sensor_reading.dart';
import 'package:bike_control/services/sensors/sensor_source.dart';
import 'package:bike_control/utils/core.dart';
import 'package:bike_control/utils/iap/iap_manager.dart';
import 'package:bike_control/widgets/ui/loading_widget.dart';
import 'package:bike_control/widgets/ui/pro_badge.dart';
import 'package:bike_control/widgets/ui/setting_tile.dart';
import 'package:bike_control/widgets/ui/small_progress_indicator.dart';
import 'package:bike_control/widgets/ui/toast.dart';
import 'package:prop/prop.dart' show LogLevel;
import 'package:shadcn_flutter/shadcn_flutter.dart';

/// Per-[SensorQuantity] label, icon and unit-formatted value text — shared
/// wherever a quantity needs to be presented, not just this file's row.
extension SensorQuantityPresentation on SensorQuantity {
  String title(AppLocalizations l10n) => switch (this) {
    SensorQuantity.heartRate => l10n.sensorQuantityHeartRate,
    SensorQuantity.cadence => l10n.sensorQuantityCadence,
    SensorQuantity.power => l10n.sensorQuantityPower,
    SensorQuantity.speed => l10n.sensorQuantitySpeed,
  };

  IconData get icon => switch (this) {
    SensorQuantity.heartRate => LucideIcons.heart,
    SensorQuantity.cadence => LucideIcons.rotateCw,
    SensorQuantity.power => LucideIcons.zap,
    SensorQuantity.speed => LucideIcons.gauge,
  };

  /// [value] formatted with this quantity's unit (bpm / rpm / W) — the
  /// headline reading on a quantity row and the live reading on each of its
  /// toggle-group pills both go through this, so the two can never disagree
  /// on units.
  String formatValue(AppLocalizations l10n, int value) => switch (this) {
    SensorQuantity.heartRate => l10n.sensorValueHeartRate(value),
    SensorQuantity.cadence => l10n.sensorValueCadence(value),
    SensorQuantity.power => l10n.sensorValuePower(value),
    SensorQuantity.speed => '$value',
  };
}

/// Kind label for a sensor's [SensorSource.provides] set — shown on every
/// toggle-group pill so the rider can tell what they are looking at even
/// before reading the device name (e.g. a power meter listed as a cadence
/// source, since a crank-based meter's [provides] always includes both).
///
/// Checked in this order deliberately: [BlePowerDevice]'s source provides
/// both power AND cadence (see its doc comment), so a power meter must be
/// recognised as one before the cadence check ever gets a chance to
/// mislabel it as a plain cadence sensor.
String _sensorKindLabel(AppLocalizations l10n, Set<SensorQuantity> provides) {
  if (provides.contains(SensorQuantity.power)) return l10n.sensorKindPowerMeter;
  if (provides.contains(SensorQuantity.cadence)) return l10n.sensorKindCadenceSensor;
  return l10n.sensorKindHeartRateMonitor;
}

/// One selectable, non-trainer entry in a [SensorQuantitySelector]'s toggle
/// group.
///
/// [device] is non-null only while NOT yet connected: `SensorHub.register`
/// fires from `Connection`'s post-connect hook, never before (see its doc
/// comment), so a [source] that is already reachable through
/// [SensorHub.sourcesFor] is — by construction — currently connected, and
/// there is nothing left for a tap on it to connect. A nearby sensor that
/// has never connected has no hub entry at all yet; [device] is what a tap
/// on THAT pill connects, via `Connection.connectDevice`.
class _SourceCandidate {
  const _SourceCandidate(this.source, {this.device});

  final SensorSource source;
  final BleSensorDevice? device;

  bool get isConnected => device == null;
}

/// Lets the rider choose where a single metric comes from: the trainer
/// (default, `null`) or a source that provides it — a shadcn toggle group
/// (`SelectedButton` pills inside a `ButtonGroup`) listing the trainer first,
/// then every sensor known to provide this quantity, INCLUDING ones not yet
/// connected. Picking one of those is how the rider connects it — see
/// [_select].
///
/// Generic over [SensorQuantity] on purpose — heart rate, cadence and power
/// all plug into this same widget; speed has no source yet, so
/// `SensorsSection` never mounts a row for it.
class SensorQuantitySelector extends StatefulWidget {
  final SensorHub hub;
  final SensorQuantity quantity;

  const SensorQuantitySelector({super.key, required this.hub, required this.quantity});

  @override
  State<SensorQuantitySelector> createState() => _SensorQuantitySelectorState();
}

class _SensorQuantitySelectorState extends State<SensorQuantitySelector> {
  late StreamSubscription<BaseDevice> _connectionSub;

  @override
  void initState() {
    super.initState();
    // Reflects a newly discovered or newly (dis)connected sensor live,
    // without the rider leaving and reopening this page — mirrors the
    // connectionStream listener the deleted SensorDiscoverySection used for
    // the exact same reason.
    _connectionSub = core.connection.connectionStream.listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _connectionSub.cancel();
    super.dispose();
  }

  /// Every selectable, non-trainer source for this row's quantity:
  /// already-registered ones (connected — see
  /// [_SourceCandidate]'s doc comment) from the hub, plus nearby
  /// [BleSensorDevice]s that provide this quantity and are not registered
  /// yet. `registeredIds` also protects against listing an already-connected
  /// device twice for the brief window where it is both registered in the
  /// hub AND still present in `core.connection.devices`.
  List<_SourceCandidate> _candidates() {
    final quantity = widget.quantity;
    final registered = widget.hub.sourcesFor(quantity);
    final registeredIds = registered.map((s) => s.id).toSet();
    final nearby = core.connection.devices
        .whereType<BleSensorDevice>()
        .where((d) => d.source.provides.contains(quantity) && !registeredIds.contains(d.source.id));
    return [
      for (final source in registered) _SourceCandidate(source),
      for (final device in nearby) _SourceCandidate(device.source, device: device),
    ];
  }

  /// Picking an external source is a Pro feature, consistent with Bridge and
  /// Virtual Shifting. Deliberately checks `isProEnabledForCurrentDevice`
  /// rather than the `OrDidPurchaseOld` variant used elsewhere in the app —
  /// the one-time-purchase grandfather does not extend to this. Gated ahead
  /// of everything else below: a rider who is not entitled must never reach
  /// the connect step, which has a real side effect on OTHER apps' pairings.
  ///
  /// For a not-yet-connected [candidate] (see [_SourceCandidate]'s doc
  /// comment), selection IS the connection request: the per-device consent
  /// flag is persisted BEFORE `connect()` is ever called —
  /// `shouldAutoConnect` reads it and `connect()` early-returns otherwise
  /// (see `BleHeartRateDevice.shouldAutoConnect`) — and only then is the
  /// device actually connected. This ordering is load-bearing; do not
  /// reorder it. Mirrors exactly how the deleted `SensorDiscoverySection`
  /// did its own connect.
  Future<void> _select(_SourceCandidate? candidate) async {
    try {
      final sourceId = candidate?.source.id;
      if (sourceId != null && !IAPManager.instance.isProEnabledForCurrentDevice) {
        final granted = await IAPManager.instance.ensureProForFeature(
          context,
          featureName: widget.quantity.title(AppLocalizations.of(context)),
        );
        if (!granted) {
          // Nothing changed in the hub — force a rebuild so the toggle group
          // snaps back to the hub's actual selection instead of lingering on
          // the tapped-but-rejected value.
          if (mounted) setState(() {});
          return;
        }
      }

      widget.hub.select(widget.quantity, sourceId);
      // Persists every quantity's CURRENT selection, not just this one — see
      // `SensorHub.persistSelections`.
      await widget.hub.persistSelections(core.settings);

      final device = candidate?.device;
      if (device != null) {
        await core.settings.setSensorAutoConnect(device.device.deviceId, true);
        await core.connection.connectDevice(device);
      }
      if (mounted) setState(() {});
    } catch (e, s) {
      // Recorded here with a specific context AND rethrown: the enclosing
      // `_SensorToggle`'s `LoadingWidget` needs the exception too, to flip
      // into its own connecting-failed UI (see that widget's doc comment).
      await recordError(e, s, context: 'SensorQuantitySelector._select');
      rethrow;
    }
  }

  SensorSource? _sourceById(String id) {
    for (final source in widget.hub.sources) {
      if (source.id == id) return source;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final hub = widget.hub;
    final quantity = widget.quantity;
    final isPro = IAPManager.instance.isProEnabledForCurrentDevice;
    final candidates = _candidates();

    return ValueListenableBuilder<bool>(
      valueListenable: hub.droppedOut(quantity),
      builder: (context, droppedOut, _) {
        return ValueListenableBuilder<int?>(
          valueListenable: hub.resolved(quantity),
          builder: (context, resolved, _) {
            final selectedId = hub.selectionFor(quantity);

            return SettingTile(
              icon: quantity.icon,
              title: quantity.title(l10n),
              subtitle: resolved != null ? quantity.formatValue(l10n, resolved) : l10n.sensorNoReadingYet,
              trailing: !isPro ? ProBadge(key: Key('sensor-pro-badge-${quantity.name}')) : null,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 8,
                children: [
                  ...?_statusIndicator(context, l10n, selectedId, droppedOut),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: ButtonGroup(
                      children: [
                        _SensorToggle(
                          key: Key('sensor-toggle-${quantity.name}-trainer'),
                          selected: selectedId == null,
                          onSelect: () => _select(null),
                          child: Text(l10n.sensorSourceTrainer),
                        ),
                        for (final candidate in candidates)
                          _SensorToggle(
                            key: Key('sensor-toggle-${quantity.name}-${candidate.source.id}'),
                            selected: selectedId == candidate.source.id,
                            onSelect: () => _select(candidate),
                            child: _CandidateContent(quantity: quantity, candidate: candidate),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  /// The hub cannot tell "never reported" apart from "went stale" — both
  /// collapse to `droppedOut == true` (see `SensorHub._publish`). Presenting
  /// that as "signal lost" the instant a rider picks a source, before its
  /// first notification ever arrives, would read as a bug. Distinguish the
  /// two here using the source's own raw last reading, which is null only
  /// when it has genuinely never reported anything for this quantity.
  List<Widget>? _statusIndicator(BuildContext context, AppLocalizations l10n, String? selectedId, bool droppedOut) {
    if (selectedId == null || !droppedOut) return null;

    final cs = Theme.of(context).colorScheme;
    final everReported = _sourceById(selectedId)?.readingFor(widget.quantity).value != null;

    if (!everReported) {
      // A static hourglass, not a spinner: an indeterminate animation never
      // settles, which would make every widget test touching this state
      // hang on `pumpAndSettle`. It also reads calmer than motion for a
      // state that is expected and may last a while (a strap that is paired
      // but not yet worn, say).
      return [
        Row(
          key: Key('sensor-waiting-${widget.quantity.name}'),
          mainAxisSize: MainAxisSize.min,
          spacing: 6,
          children: [
            Icon(LucideIcons.hourglass, size: 14, color: cs.mutedForeground),
            Text(l10n.sensorAwaitingFirstReading, style: TextStyle(fontSize: 12, color: cs.mutedForeground)),
          ],
        ),
      ];
    }

    return [
      Row(
        key: Key('sensor-dropout-${widget.quantity.name}'),
        mainAxisSize: MainAxisSize.min,
        spacing: 6,
        children: [
          const Icon(LucideIcons.wifiOff, size: 14, color: Color(0xFFF59E0B)),
          Text(l10n.sensorDroppedOut, style: TextStyle(fontSize: 12, color: cs.mutedForeground)),
        ],
      ),
    ];
  }
}

/// A pill's inner content for a non-trainer [_SourceCandidate]: its display
/// name, what kind of sensor it is, and — the two things the author's
/// feedback specifically called out as missing from the old radio-icon row —
/// whether it is connected and its own live reading when it is.
class _CandidateContent extends StatelessWidget {
  const _CandidateContent({required this.quantity, required this.candidate});

  final SensorQuantity quantity;
  final _SourceCandidate candidate;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final metaStyle = TextStyle(fontSize: 11, color: cs.mutedForeground);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      spacing: 2,
      children: [
        Text(candidate.source.displayName, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        Row(
          mainAxisSize: MainAxisSize.min,
          spacing: 4,
          children: [
            Text(_sensorKindLabel(l10n, candidate.source.provides), style: metaStyle),
            Text('·', style: metaStyle),
            if (!candidate.isConnected)
              Text(l10n.notConnected, style: metaStyle)
            else
              ValueListenableBuilder<SensorReading?>(
                valueListenable: candidate.source.readingFor(quantity),
                builder: (context, reading, _) => Text(
                  reading != null ? quantity.formatValue(l10n, reading.value) : l10n.sensorAwaitingFirstReading,
                  style: metaStyle,
                ),
              ),
          ],
        ),
      ],
    );
  }
}

/// One toggle-group pill. Wraps [LoadingWidget] so selecting a not-yet
/// -connected sensor — which also connects it, see
/// `SensorQuantitySelector._select` — shows a connecting spinner in place of
/// its usual content, and a failure is recorded (`recordError`, inside
/// [LoadingWidget]), toasted, AND left visible on the pill itself until the
/// next attempt. Selecting the trainer or an already-connected sensor goes
/// through the exact same widget — [LoadingWidget.futureCallback] just
/// resolves almost immediately for those, so the loading/failure UI is
/// there if a rare persistence error hits, without needing a second code
/// path.
class _SensorToggle extends StatefulWidget {
  const _SensorToggle({super.key, required this.selected, required this.onSelect, required this.child});

  final bool selected;
  final Future<void> Function() onSelect;
  final Widget child;

  @override
  State<_SensorToggle> createState() => _SensorToggleState();
}

class _SensorToggleState extends State<_SensorToggle> {
  bool _failed = false;

  Future<void> _run() async {
    setState(() => _failed = false);
    await widget.onSelect();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return LoadingWidget(
      futureCallback: _run,
      onErrorCallback: (context, error) {
        setState(() => _failed = true);
        buildToast(level: LogLevel.LOGLEVEL_WARNING, title: l10n.sensorConnectFailed);
      },
      renderChild: (isLoading, tap) => SelectedButton(
        value: widget.selected,
        enabled: !isLoading,
        onChanged: (_) => tap?.call(),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          spacing: 6,
          children: [
            widget.child,
            if (isLoading)
              const SmallProgressIndicator()
            else if (_failed) ...[
              const Icon(LucideIcons.triangleAlert, size: 12, color: Color(0xFFEF4444)),
              Text(l10n.sensorConnectFailed, style: const TextStyle(fontSize: 11, color: Color(0xFFEF4444))),
            ],
          ],
        ),
      ),
    );
  }
}
