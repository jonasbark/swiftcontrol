import 'package:bike_control/bluetooth/emulation/emulation_manager.dart';
import 'package:bike_control/bluetooth/emulation/emulation_profile.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

/// Debug-only interactive controls for an emulated device: inject protocol
/// frames per input, review decoded app→device writes, and exercise the
/// connection UX (drop / signal strength).
class EmulationCard extends StatelessWidget {
  const EmulationCard({super.key, required this.session});

  final EmulationSession session;

  @override
  Widget build(BuildContext context) {
    return Card(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 12,
        children: [
          if (session.inputs.isNotEmpty)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [for (final input in session.inputs) _buildInput(input)],
            ),
          ValueListenableBuilder<List<String>>(
            valueListenable: session.writeLog,
            builder: (context, log, _) {
              if (log.isEmpty) return const SizedBox.shrink();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 4,
                children: [
                  const Text('WRITES FROM APP').xSmall.bold.muted,
                  for (final line in log.reversed.take(8)) Text(line).xSmall.muted,
                ],
              );
            },
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlineButton(
                size: ButtonSize.small,
                onPressed: session.dropConnection,
                child: const Text('Drop connection'),
              ),
              OutlineButton(
                size: ButtonSize.small,
                onPressed: () => session.setRssi(-85),
                child: const Text('Weak signal'),
              ),
              OutlineButton(
                size: ButtonSize.small,
                onPressed: () => session.setRssi(-50),
                child: const Text('Strong signal'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInput(EmulatedInput input) {
    return switch (input) {
      EmulatedButton button => Button(
          style: ButtonStyle.outline(),
          onPressed: () {},
          onTapDown: (_) => button.onDown(),
          onTapUp: (_) => button.onUp(),
          child: Text(button.label),
        ),
      EmulatedAction action => Button(
          style: ButtonStyle.outline(),
          onPressed: action.run,
          child: Text(action.label),
        ),
    };
  }
}
