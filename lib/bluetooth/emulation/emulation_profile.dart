import 'emulated_ble_platform.dart';
import 'emulation_manager.dart';

enum EmulationCategory { controller, steering, accessory }

/// One emulatable device: how to build its fake peripheral, how to script its
/// reactions, and which interactive inputs the Emulation card offers.
class EmulationProfile {
  const EmulationProfile({
    required this.name,
    required this.category,
    required this.build,
    this.onRegistered,
    this.inputs,
    this.decodeWrite,
  });

  final String name;
  final EmulationCategory category;

  /// Builds the peripheral. The deviceId must be stable and
  /// 'emulated:'-prefixed so re-adding the same profile is idempotent.
  final FakePeripheral Function() build;

  /// Scripts peripheral reactions (e.g. handshake auto-responses). Runs once
  /// when the session starts, before the write-log wrapper is installed.
  final void Function(FakeUniversalBlePlatform ble, FakePeripheral peripheral)? onRegistered;

  /// Interactive inputs for the Emulation card.
  final List<EmulatedInput> Function(EmulationSession session)? inputs;

  /// Decodes an app→device write for the write log ([characteristicUuid] is
  /// lowercase); null return = not logged.
  final String? Function(String characteristicUuid, List<int> value)? decodeWrite;
}

sealed class EmulatedInput {
  const EmulatedInput(this.label);
  final String label;
}

/// Press-and-hold button: [onDown] injects the pressed frame, [onUp] the
/// released frame — the app's real long-press/double-click timing applies.
class EmulatedButton extends EmulatedInput {
  const EmulatedButton(super.label, {required this.onDown, required this.onUp});
  final void Function() onDown;
  final void Function() onUp;
}

/// One-shot action (self-releasing protocols, calibration bursts, taps).
class EmulatedAction extends EmulatedInput {
  const EmulatedAction(super.label, {required this.run});
  final void Function() run;
}
