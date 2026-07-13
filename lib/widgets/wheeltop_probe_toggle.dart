import 'package:bike_control/utils/core.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

/// Opt-in switch for the WHEELTOP keepalive experiment (see WheeltopProbe).
///
/// English-only on purpose: a temporary beta diagnostic driven through
/// support, expected to disappear once the TX status-frame reply is known.
class WheeltopProbeToggle extends StatefulWidget {
  const WheeltopProbeToggle({super.key});

  @override
  State<WheeltopProbeToggle> createState() => _WheeltopProbeToggleState();
}

class _WheeltopProbeToggleState extends State<WheeltopProbeToggle> {
  late bool _enabled = core.settings.getWheeltopProbeEnabled();

  void _onChanged(bool value) {
    setState(() => _enabled = value);
    core.settings.setWheeltopProbeEnabled(value);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 4,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(child: const Text('Keepalive experiment (beta)').small.semiBold),
            Switch(value: _enabled, onChanged: _onChanged),
          ],
        ),
        const Text(
          'TX shifters drop the connection a few seconds after connecting because the app '
          'does not yet know how to answer their status frames. This experiment tries one '
          'candidate answer per reconnect and records the outcome in the log — sharing that '
          'log with support helps find the answer that keeps the shifter connected.',
        ).xSmall,
      ],
    );
  }
}
