import 'package:bike_control/gen/l10n.dart';
import 'package:bike_control/main.dart';
import 'package:bike_control/services/sensors/sensor_hub.dart';
import 'package:bike_control/services/sensors/sensor_quantity.dart';
import 'package:bike_control/services/sensors/sensor_source.dart';
import 'package:bike_control/utils/core.dart';
import 'package:bike_control/utils/iap/iap_manager.dart';
import 'package:bike_control/widgets/ui/pro_badge.dart';
import 'package:bike_control/widgets/ui/setting_tile.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

/// Per-[SensorQuantity] label and icon, shared between this file's selector
/// and `SensorsSection`'s paired-source list.
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
}

/// Lets the rider choose where a single metric comes from: the trainer
/// (default, `null`) or a registered [SensorSource] that provides it.
///
/// Generic over [SensorQuantity] on purpose — today only heart rate has a
/// real source behind it (see `SensorsSection`), but cadence/power/speed are
/// meant to plug into this same widget once their sources exist, with no
/// further UI work.
class SensorQuantitySelector extends StatefulWidget {
  final SensorHub hub;
  final SensorQuantity quantity;

  const SensorQuantitySelector({super.key, required this.hub, required this.quantity});

  @override
  State<SensorQuantitySelector> createState() => _SensorQuantitySelectorState();
}

class _SensorQuantitySelectorState extends State<SensorQuantitySelector> {
  /// Picking an external source is a Pro feature, consistent with Bridge and
  /// Virtual Shifting. Deliberately checks `isProEnabledForCurrentDevice`
  /// rather than the `OrDidPurchaseOld` variant used elsewhere in the app —
  /// the one-time-purchase grandfather does not extend to this.
  Future<void> _handleChanged(String? sourceId) async {
    try {
      if (sourceId != null && !IAPManager.instance.isProEnabledForCurrentDevice) {
        final granted = await IAPManager.instance.ensureProForFeature(
          context,
          featureName: widget.quantity.title(AppLocalizations.of(context)),
        );
        if (!granted) {
          // Nothing changed in the hub — force a rebuild so the Select snaps
          // back to the hub's actual selection instead of lingering on the
          // tapped-but-rejected value.
          if (mounted) setState(() {});
          return;
        }
      }
      widget.hub.select(widget.quantity, sourceId);
      // Persists every quantity's CURRENT selection, not just this one — see
      // `SensorHub.persistSelections`. That is deliberately safe to call at
      // any time: a different quantity's still-pending selection (its source
      // has not registered yet, e.g. the rider opened this page before their
      // strap connected) lives in the hub's in-memory selection map either
      // way, so this sweep writes it back unchanged instead of clearing it.
      await widget.hub.persistSelections(core.settings);
      if (mounted) setState(() {});
    } catch (e, s) {
      await recordError(e, s, context: 'SensorQuantitySelector._handleChanged');
    }
  }

  SensorSource? _sourceById(String id) {
    for (final source in widget.hub.sources) {
      if (source.id == id) return source;
    }
    return null;
  }

  String _labelFor(AppLocalizations l10n, String? id) {
    if (id == null) return l10n.sensorSourceTrainer;
    return _sourceById(id)?.displayName ?? id;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final hub = widget.hub;
    final quantity = widget.quantity;
    final isPro = IAPManager.instance.isProEnabledForCurrentDevice;

    return ValueListenableBuilder<bool>(
      valueListenable: hub.droppedOut(quantity),
      builder: (context, droppedOut, _) {
        return ValueListenableBuilder<int?>(
          valueListenable: hub.resolved(quantity),
          builder: (context, resolved, _) {
            final selectedId = hub.selectionFor(quantity);
            final sources = hub.sourcesFor(quantity);

            return SettingTile(
              icon: quantity.icon,
              title: quantity.title(l10n),
              subtitle: l10n.sensorSourceHint,
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                spacing: 6,
                children: [
                  if (!isPro) ProBadge(key: Key('sensor-pro-badge-${quantity.name}')),
                  Select<String?>(
                    value: selectedId,
                    itemBuilder: (context, id) => Text(_labelFor(l10n, id)),
                    placeholder: Text(l10n.sensorSourceTrainer),
                    popup: SelectPopup(
                      items: SelectItemList(
                        children: [
                          SelectItemButton<String?>(
                            value: null,
                            child: Text(l10n.sensorSourceTrainer),
                          ),
                          for (final source in sources)
                            SelectItemButton<String?>(
                              value: source.id,
                              child: Text(source.displayName),
                            ),
                        ],
                      ),
                    ).call,
                    onChanged: _handleChanged,
                  ),
                ],
              ),
              child: _statusIndicator(context, l10n, selectedId, droppedOut),
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
  Widget? _statusIndicator(BuildContext context, AppLocalizations l10n, String? selectedId, bool droppedOut) {
    if (selectedId == null || !droppedOut) return null;

    final cs = Theme.of(context).colorScheme;
    final everReported = _sourceById(selectedId)?.readingFor(widget.quantity).value != null;

    if (!everReported) {
      // A static hourglass, not a spinner: an indeterminate animation never
      // settles, which would make every widget test touching this state
      // hang on `pumpAndSettle`. It also reads calmer than motion for a
      // state that is expected and may last a while (a strap that is paired
      // but not yet worn, say).
      return Row(
        key: Key('sensor-waiting-${widget.quantity.name}'),
        mainAxisSize: MainAxisSize.min,
        spacing: 6,
        children: [
          Icon(LucideIcons.hourglass, size: 14, color: cs.mutedForeground),
          Text(l10n.sensorAwaitingFirstReading, style: TextStyle(fontSize: 12, color: cs.mutedForeground)),
        ],
      );
    }

    return Row(
      key: Key('sensor-dropout-${widget.quantity.name}'),
      mainAxisSize: MainAxisSize.min,
      spacing: 6,
      children: [
        const Icon(LucideIcons.wifiOff, size: 14, color: Color(0xFFF59E0B)),
        Text(l10n.sensorDroppedOut, style: TextStyle(fontSize: 12, color: cs.mutedForeground)),
      ],
    );
  }
}
