import 'dart:async';

import 'package:bike_control/bluetooth/devices/base_device.dart';
import 'package:bike_control/bluetooth/devices/sensors/ble_heart_rate_device.dart';
import 'package:bike_control/gen/l10n.dart';
import 'package:bike_control/utils/core.dart';
import 'package:bike_control/widgets/ui/loading_widget.dart';
import 'package:bike_control/widgets/ui/setting_tile.dart';
import 'package:bike_control/widgets/ui/small_progress_indicator.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

/// Heart rate straps the scanner has already discovered but not connected,
/// each with an explicit Connect action.
///
/// A strap deliberately never auto-connects (`BleHeartRateDevice
/// .shouldAutoConnect`) — most only allow a single simultaneous BLE
/// connection, and auto-connecting would silently take one away from Zwift,
/// a bike computer or a watch. That is also why `SensorsSection`'s own
/// paired-sources list can never be this section: it only ever shows a
/// source that has ALREADY connected (`SensorHub.register` fires from
/// `Connection`'s post-connect hook, never before). Without this list, a
/// discovered strap has no route to becoming a source at all — this is that
/// missing rider action.
class SensorDiscoverySection extends StatefulWidget {
  const SensorDiscoverySection({super.key});

  @override
  State<SensorDiscoverySection> createState() => _SensorDiscoverySectionState();
}

class _SensorDiscoverySectionState extends State<SensorDiscoverySection> {
  late StreamSubscription<BaseDevice> _connectionSub;

  @override
  void initState() {
    super.initState();
    // Reflects newly discovered or newly connected straps live, without the
    // rider leaving and reopening this page — mirrors ScanWidget/DevicePage's
    // own connectionStream listener.
    _connectionSub = core.connection.connectionStream.listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _connectionSub.cancel();
    super.dispose();
  }

  /// Persists explicit consent BEFORE connecting — `shouldAutoConnect` gates
  /// on it, so connecting first would just re-hit the same early return the
  /// gate exists for. Routes through `connectDevice`, not a bare
  /// `device.connect()`: this device already sits in `core.connection
  /// .devices` from its original discovery, and `connectDevice` is the
  /// documented, tested path for (re)connecting a device already in that
  /// list — a bare call can leave `isConnected` stuck once a listener has
  /// been torn down (see its doc comment).
  Future<void> _connect(BleHeartRateDevice device) async {
    await core.settings.setSensorAutoConnect(device.device.deviceId, true);
    await core.connection.connectDevice(device);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final nearby = core.connection.devices.whereType<BleHeartRateDevice>().where((d) => !d.isConnected).toList();
    if (nearby.isEmpty) return const SizedBox.shrink();

    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 8,
      children: [
        Text(
          l10n.sensorsNearbyTitle,
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: cs.mutedForeground),
        ),
        for (final device in nearby)
          SettingTile(
            key: ValueKey('sensor-nearby-${device.device.deviceId}'),
            icon: LucideIcons.radio,
            title: device.name,
            subtitle: l10n.notConnected,
            trailing: LoadingWidget(
              futureCallback: () => _connect(device),
              renderChild: (isLoading, tap) => Button(
                style: ButtonStyle.outline(),
                onPressed: tap,
                leading: isLoading ? const SmallProgressIndicator() : null,
                child: Text(l10n.connect),
              ),
            ),
          ),
      ],
    );
  }
}
