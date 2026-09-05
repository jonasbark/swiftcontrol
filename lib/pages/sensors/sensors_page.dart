import 'package:bike_control/gen/l10n.dart';
import 'package:bike_control/pages/sensors/sensors_section.dart';
import 'package:bike_control/utils/core.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

/// Global entry point for external-sensor settings.
///
/// `SensorsSection` is also mounted per-trainer on `ProxyDeviceDetailsPage`,
/// which answers "where does my heart rate come from" for a rider looking at
/// a bridged trainer. But standalone mode — BikeControl advertising as a
/// plain heart rate monitor with no trainer bridged at all — exists
/// precisely for riders who never bridge a trainer through the app, so that
/// per-trainer copy is unreachable for them. This page, opened from
/// `HomeExtras`' "Sensors" row on the home screen, is reachable regardless of
/// whether any trainer is connected.
class SensorsPage extends StatelessWidget {
  const SensorsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      headers: [
        AppBar(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          leading: [
            IconButton.ghost(
              icon: const Icon(LucideIcons.arrowLeft, size: 24),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
          title: Text(
            AppLocalizations.of(context).sensorsSectionTitle,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600, letterSpacing: -0.3),
          ),
          trailing: [
            IconButton.ghost(
              icon: Icon(LucideIcons.x, size: 22, color: Theme.of(context).colorScheme.mutedForeground),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
          backgroundColor: Theme.of(context).colorScheme.background,
        ),
        const Divider(),
      ],
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 800),
            child: SensorsSection(hub: core.sensors),
          ),
        ),
      ),
    );
  }
}
