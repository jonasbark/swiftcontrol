/// The world the setup chain is built from, as plain data.
///
/// [ChainInputs] is the seam between the app's live state (BLE, settings, the
/// `core` singleton) and the chain's derivation logic. `HomePage` fills one in
/// from `core`; [buildChain] turns it into cards. Tests construct one directly
/// and never touch Bluetooth.
library;

/// How present a known device is right now.
///
/// The distinction between [lost] and [remembered] is the whole reason this
/// enum exists rather than a bare `isConnected` bool: a controller that
/// dropped mid-ride is a red problem, while one that simply hasn't been
/// switched on since the app started is amber. A fresh app launch with the
/// controller in a drawer must not paint the screen red.
enum DevicePresence {
  /// Connected and usable.
  connected,

  /// Rebooting because of an automatic reset — it comes back by itself, so it
  /// is never a problem.
  resetting,

  /// Was connected during this app session and dropped.
  lost,

  /// Known from a previous session, not seen yet this time.
  remembered,

  /// In range and known to the app, but never actually connected — a trainer
  /// the scanner just found, say. It has nothing to lose, so it can never be
  /// [lost]; treating it as such is how a brand-new trainer ended up shouting
  /// "lost connection" on a screen it had only just appeared on.
  discovered,
}

class ControllerInput {
  const ControllerInput({
    required this.deviceId,
    required this.name,
    required this.presence,
    required this.hasMappedButtons,
    this.requiresBluetooth = true,
  });

  final String deviceId;
  final String name;
  final DevicePresence presence;

  /// Whether the active keymap assigns at least one action to one of this
  /// device's buttons.
  final bool hasMappedButtons;

  /// False for controllers that don't ride on BLE (USB/OS gamepads, the
  /// phone's gyroscope). Their card omits the Bluetooth step, which would
  /// otherwise be a permanently ticked line that means nothing.
  final bool requiresBluetooth;
}

class TrainerInput {
  const TrainerInput({
    required this.deviceId,
    required this.name,
    required this.presence,
    required this.gearsConfigured,
    this.gearsSummary,
    this.metrics,
  });

  final String deviceId;
  final String name;
  final DevicePresence presence;

  /// Whether an active [ShiftingConfig] exists for this trainer.
  final bool gearsConfigured;

  /// e.g. "24 gears · ratio 2.40".
  final String? gearsSummary;

  /// Live telemetry for the ready-state status line, e.g. "250 W · 90 rpm".
  final String? metrics;
}

class AppInput {
  const AppInput({
    this.name,
    this.selfHosted = false,
    this.hasEnabledConnection = false,
    this.isConnected = false,
    this.wasConnectedThisSession = false,
    this.connectionSummary,
  });

  /// The selected trainer app, or null when the rider hasn't picked one.
  final String? name;

  /// BikeControl-as-trainer-app runs the workout itself, so "which connection
  /// method reaches it" is meaningless — both connection steps are satisfied
  /// by definition.
  final bool selfHosted;

  final bool hasEnabledConnection;
  final bool isConnected;

  /// Drives the red "lost connection" state, same rule as devices.
  final bool wasConnectedThisSession;

  /// e.g. "Network" — which method is carrying the commands.
  final String? connectionSummary;
}

class ChainInputs {
  const ChainInputs({
    this.bluetoothReady = true,
    this.controllers = const [],
    this.trainer,
    this.app = const AppInput(),
  });

  /// BLE permission granted *and* the adapter powered on.
  final bool bluetoothReady;

  /// Every controller the app knows about — live and remembered — in display
  /// order.
  final List<ControllerInput> controllers;

  /// The smart trainer, when one is known. Null renders the optional
  /// placeholder card.
  final TrainerInput? trainer;

  final AppInput app;
}
