import 'dart:async';

import 'package:bike_control/bluetooth/devices/base_device.dart';
import 'package:bike_control/bluetooth/devices/sensors/ble_sensor_device.dart';
import 'package:bike_control/gen/l10n.dart';
import 'package:bike_control/main.dart';
import 'package:bike_control/services/sensors/sensor_quantity.dart';
import 'package:bike_control/services/sensors/sensor_source.dart';
import 'package:bike_control/utils/core.dart';
import 'package:bike_control/utils/iap/iap_manager.dart';
import 'package:bike_control/widgets/ui/loading_widget.dart';
import 'package:bike_control/widgets/ui/small_progress_indicator.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

/// The tile's own quantity-scoped label. Kept local to this file rather than
/// resurrecting the deleted `SensorQuantitySelector`'s
/// `SensorQuantityPresentation` extension: nothing else in the surviving
/// tree needs a title/icon per [SensorQuantity] any more, only this sheet.
String _quantityTitle(AppLocalizations l10n, SensorQuantity quantity) => switch (quantity) {
  SensorQuantity.heartRate => l10n.sensorQuantityHeartRate,
  SensorQuantity.cadence => l10n.sensorQuantityCadence,
  SensorQuantity.power => l10n.sensorQuantityPower,
  SensorQuantity.speed => l10n.sensorQuantitySpeed,
};

/// [value] formatted with [quantity]'s unit — ported from the same deleted
/// extension's `formatValue`.
String _formatReading(AppLocalizations l10n, SensorQuantity quantity, int value) => switch (quantity) {
  SensorQuantity.heartRate => l10n.sensorValueHeartRate(value),
  SensorQuantity.cadence => l10n.sensorValueCadence(value),
  SensorQuantity.power => l10n.sensorValuePower(value),
  SensorQuantity.speed => '$value',
};

/// Kind label for a sensor's [SensorSource.provides] set. Checked in this
/// order deliberately: a power meter's source always provides both power AND
/// cadence (`BlePowerDevice`'s doc comment), so it must be recognised as one
/// before the cadence check gets a chance to mislabel it as a plain cadence
/// sensor. Ported from the deleted `sensor_quantity_selector.dart` /
/// `sensors_section.dart`, which each carried an identical copy of this.
String _kindLabel(AppLocalizations l10n, Set<SensorQuantity> provides) {
  if (provides.contains(SensorQuantity.power)) return l10n.sensorKindPowerMeter;
  if (provides.contains(SensorQuantity.cadence)) return l10n.sensorKindCadenceSensor;
  return l10n.sensorKindHeartRateMonitor;
}

/// Opens the picker for [quantity]: Trainer, plus every sensor that provides
/// it, connected or not — the tap target the tile's source row opens (see
/// `MetricSourceRow`).
Future<void> openSensorSourcePicker(BuildContext context, {required SensorQuantity quantity}) {
  return openSheet<void>(
    context: context,
    position: OverlayPosition.bottom,
    builder: (sheetContext) => SensorSourcePicker(quantity: quantity),
  );
}

/// One selectable, non-trainer entry — ported unchanged from the deleted
/// `SensorQuantitySelector._SourceCandidate`. [device] is non-null only
/// while NOT yet connected: a [source] already reachable through
/// `SensorHub.sourcesFor` is, by construction, currently connected (see
/// `SensorHub.register`'s doc comment), so there is nothing left for a tap
/// to connect. A nearby sensor that has never connected has no hub entry
/// yet; [device] is what a tap on it connects.
class _SourceCandidate {
  const _SourceCandidate(this.source, {this.device});

  final SensorSource source;
  final BleSensorDevice? device;

  bool get isConnected => device == null;
}

/// Trainer plus every sensor that provides [quantity], connected or not —
/// the picker `MetricSourceRow.onTap` opens. Ports the deleted
/// `SensorQuantitySelector`'s selection logic and the deleted
/// `_ConnectedSensorsSection`'s disconnect logic onto one sheet scoped to a
/// single quantity, since the signals grid is now the only sensor surface
/// and a rider reaches "what feeds my heart rate" from the Heart tile
/// directly rather than a separate page.
class SensorSourcePicker extends StatefulWidget {
  const SensorSourcePicker({super.key, required this.quantity});

  final SensorQuantity quantity;

  @override
  State<SensorSourcePicker> createState() => _SensorSourcePickerState();
}

class _SensorSourcePickerState extends State<SensorSourcePicker> {
  late StreamSubscription<BaseDevice> _connectionSub;

  @override
  void initState() {
    super.initState();
    // Reflects a newly discovered, connected or disconnected sensor live,
    // without the rider closing and reopening the sheet — mirrors the
    // listener `SensorQuantitySelector` used for the same reason.
    _connectionSub = core.connection.connectionStream.listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _connectionSub.cancel();
    super.dispose();
  }

  List<_SourceCandidate> _candidates() {
    final quantity = widget.quantity;
    final registered = core.sensors.sourcesFor(quantity);
    final registeredIds = registered.map((s) => s.id).toSet();
    final nearby = core.connection.devices
        .whereType<BleSensorDevice>()
        .where((d) => d.source.provides.contains(quantity) && !registeredIds.contains(d.source.id));
    return [
      for (final source in registered) _SourceCandidate(source),
      for (final device in nearby) _SourceCandidate(device.source, device: device),
    ];
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
  /// `SensorQuantitySelector._select`, and load-bearing: the per-device
  /// consent flag is persisted BEFORE `connectDevice` is ever called —
  /// `shouldAutoConnect` reads it and `connect()` early-returns otherwise
  /// (`BleHeartRateDevice.shouldAutoConnect`'s doc comment). Do not reorder.
  Future<void> _select(_SourceCandidate? candidate) async {
    try {
      final sourceId = candidate?.source.id;
      if (sourceId != null && !IAPManager.instance.isProEnabledForCurrentDevice) {
        final granted = await IAPManager.instance.ensureProForFeature(
          context,
          featureName: _quantityTitle(AppLocalizations.of(context), widget.quantity),
        );
        if (!granted) {
          if (mounted) setState(() {});
          return;
        }
      }

      core.sensors.select(widget.quantity, sourceId);
      // Persists every quantity's CURRENT selection, not just this one — see
      // `SensorHub.persistSelections`.
      await core.sensors.persistSelections(core.settings);

      final device = candidate?.device;
      if (device != null) {
        await core.settings.setSensorAutoConnect(device.device.deviceId, true);
        await core.connection.connectDevice(device);
      }
      if (mounted) await closeSheet(context);
    } catch (e, s) {
      await recordError(e, s, context: 'SensorSourcePicker._select');
      rethrow;
    }
  }

  /// The deliberate-forget case, not a transient drop — ordering ported
  /// unchanged from the deleted `_ConnectedSensorsSection._disconnect`. The
  /// consent flag is cleared BEFORE calling `disconnect` so nothing can read
  /// a stale "yes" in the gap between the two calls; `forget: true` also
  /// drops any quantity selection pointing at this source
  /// (`Connection._unregisterSensorSource`), so the rider falls back to
  /// Trainer for it. `persistForget: false`, deliberately: this is "I'm done
  /// with my strap for now", not "this was never mine" — `true` would hide
  /// it from every future scan via the permanent ignore list.
  Future<void> _disconnect(BleSensorDevice device) async {
    try {
      await core.settings.setSensorAutoConnect(device.device.deviceId, false);
      await core.connection.disconnect(device, forget: true, persistForget: false);
      if (mounted) await closeSheet(context);
    } catch (e, s) {
      await recordError(e, s, context: 'SensorSourcePicker._disconnect');
      rethrow;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final selectedId = core.sensors.selectionFor(widget.quantity);
    final candidates = _candidates();

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 4,
          children: [
            Text(
              _quantityTitle(l10n, widget.quantity),
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const Gap(8),
            _row(
              context,
              keyId: 'sensor-source-picker-trainer-${widget.quantity.name}',
              title: l10n.sensorSourceTrainer,
              subtitle: null,
              selected: selectedId == null,
              onSelect: () => _select(null),
            ),
            for (final candidate in candidates)
              _row(
                context,
                keyId: 'sensor-source-picker-${widget.quantity.name}-${candidate.source.id}',
                title: candidate.source.displayName,
                subtitle: _statusText(l10n, candidate),
                selected: selectedId == candidate.source.id,
                onSelect: () => _select(candidate),
                connectedDevice: candidate.isConnected ? _connectedDeviceFor(candidate.source.id) : null,
              ),
          ],
        ),
      ),
    );
  }

  String _statusText(AppLocalizations l10n, _SourceCandidate candidate) {
    final kind = _kindLabel(l10n, candidate.source.provides);
    if (!candidate.isConnected) return '$kind · ${l10n.notConnected}';
    final reading = candidate.source.readingFor(widget.quantity).value;
    final status = reading != null
        ? _formatReading(l10n, widget.quantity, reading.value)
        : l10n.sensorAwaitingFirstReading;
    return '$kind · $status';
  }

  Widget _row(
    BuildContext context, {
    required String keyId,
    required String title,
    required String? subtitle,
    required bool selected,
    required Future<void> Function() onSelect,
    BleSensorDevice? connectedDevice,
  }) {
    final cs = Theme.of(context).colorScheme;
    return LoadingWidget(
      futureCallback: onSelect,
      renderChild: (isLoading, tap) => Button.ghost(
        key: Key(keyId),
        enabled: !isLoading,
        onPressed: tap,
        style: ButtonStyle.ghost().withPadding(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8)),
        child: Row(
          spacing: 8,
          children: [
            SizedBox(
              width: 16,
              child: selected ? Icon(LucideIcons.check, size: 16, color: cs.primary) : null,
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 2,
                children: [
                  Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                  if (subtitle != null) Text(subtitle, style: TextStyle(fontSize: 12, color: cs.mutedForeground)),
                ],
              ),
            ),
            if (isLoading)
              const SmallProgressIndicator()
            else if (connectedDevice != null)
              _disconnectButton(context, keyId: '$keyId-disconnect', device: connectedDevice),
          ],
        ),
      ),
    );
  }

  Widget _disconnectButton(BuildContext context, {required String keyId, required BleSensorDevice device}) {
    final cs = Theme.of(context).colorScheme;
    return LoadingWidget(
      futureCallback: () => _disconnect(device),
      renderChild: (isLoading, tap) => Button.ghost(
        key: Key(keyId),
        enabled: !isLoading,
        onPressed: tap,
        style: ButtonStyle.ghost().withPadding(padding: const EdgeInsets.all(6)),
        child: isLoading
            ? const SmallProgressIndicator()
            : Icon(LucideIcons.bluetoothOff, size: 16, color: cs.destructive),
      ),
    );
  }
}
