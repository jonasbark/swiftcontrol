import 'package:bike_control/pages/home/chain_inputs.dart';
import 'package:bike_control/pages/home/chain_state.dart';

/// Turns [ChainInputs] into the cards the home screen renders, in signal-path
/// order: your buttons → the gears BikeControl computes → the app that
/// receives them.
///
/// Pure: same inputs, same cards. Every "is this step done" rule in the app
/// lives here and nowhere else, so the banner, the card headers and the
/// checklists can never disagree.
List<ChainLink> buildChain(ChainInputs inputs) {
  return [
    ..._controllerLinks(inputs),
    _trainerLink(inputs),
    _appLink(inputs),
  ];
}

/// A device is only truly here when it is [DevicePresence.connected]. A
/// resetting device counts as connected for step purposes — it is mid-reboot,
/// not mid-failure — but its card still shows amber.
bool _isPresent(DevicePresence presence) => presence == DevicePresence.connected;

/// Maps presence onto the status of a link whose setup is otherwise complete.
LinkStatus _presenceStatus(DevicePresence presence) => switch (presence) {
  DevicePresence.connected => LinkStatus.ready,
  DevicePresence.resetting => LinkStatus.attention,
  DevicePresence.lost => LinkStatus.problem,
  DevicePresence.remembered => LinkStatus.attention,
  // Never connected is "not set up", not "something broke".
  DevicePresence.discovered => LinkStatus.off,
};

List<ChainLink> _controllerLinks(ChainInputs inputs) {
  if (inputs.controllers.isEmpty) {
    // Nothing paired ever: one placeholder card that reads as an invitation
    // rather than a fault. "Paired" and "mapped" are the two things a fresh
    // rider has to do, and neither is done.
    return [
      ChainLink(
        key: ChainLinkKey.controller,
        id: 'controller',
        status: LinkStatus.off,
        title: '',
        steps: [
          SetupStep(id: SetupStepId.controllerBluetoothReady, done: inputs.bluetoothReady),
          const SetupStep(id: SetupStepId.controllerPaired, done: false),
          const SetupStep(id: SetupStepId.controllerButtonsMapped, done: false),
        ],
      ),
    ];
  }

  return inputs.controllers.map((controller) {
    final inRange = _isPresent(controller.presence);
    final steps = <SetupStep>[
      if (controller.requiresBluetooth)
        SetupStep(id: SetupStepId.controllerBluetoothReady, done: inputs.bluetoothReady),
      // Pairing is history: once done it stays ticked even while the device is
      // away. A device we have merely discovered has no such history yet.
      SetupStep(
        id: SetupStepId.controllerPaired,
        done: controller.presence != DevicePresence.discovered,
      ),
      SetupStep(id: SetupStepId.controllerButtonsMapped, done: controller.hasMappedButtons),
      SetupStep(id: SetupStepId.controllerInRange, done: inRange),
    ];

    // An unfinished checklist outranks a healthy connection: a connected
    // controller with no buttons mapped does nothing, so it must not be green.
    final incomplete = steps.any((s) => !s.done);
    final presenceStatus = _presenceStatus(controller.presence);
    final status = incomplete && presenceStatus == LinkStatus.ready ? LinkStatus.attention : presenceStatus;

    return ChainLink(
      key: ChainLinkKey.controller,
      id: 'controller:${controller.deviceId}',
      status: status,
      title: controller.name,
      steps: steps,
      deviceId: controller.deviceId,
      // Only an absent device may be swiped away. Dismissing a live controller
      // would be a destructive accident, so the gesture simply isn't there.
      dismissible: !inRange && controller.presence != DevicePresence.resetting,
    );
  }).toList();
}

ChainLink _trainerLink(ChainInputs inputs) {
  final trainer = inputs.trainer;
  if (trainer == null) {
    // No trainer has ever been paired. The card stays as an empty, dashed,
    // explicitly optional slot — no checklist, because there is nothing the
    // rider must do here to be ready to ride.
    return const ChainLink(
      key: ChainLinkKey.trainer,
      id: 'trainer',
      status: LinkStatus.off,
      title: '',
      optional: true,
      steps: [],
    );
  }

  final paired = _isPresent(trainer.presence);
  // A checklist only earns its space once the rider has committed to bridging
  // this trainer. Before that — a trainer merely in range, or one deliberately
  // left on "let the app handle shifting" — a list of unticked boxes reads as
  // work outstanding when nothing is outstanding at all.
  final committed =
      trainer.presence != DevicePresence.discovered && trainer.presence != DevicePresence.remembered;
  // The two facts onboarding checks, in its order: the bridge is running, and
  // the trainer app has picked the virtual trainer up. Gear ratios are a
  // preference with a working default, not a step — a rider is never blocked
  // waiting to "set up gears".
  final steps = committed
      ? <SetupStep>[
          SetupStep(id: SetupStepId.trainerPaired, done: paired),
          SetupStep(id: SetupStepId.trainerAppBridged, done: trainer.appHoldsBridge, hintArg: trainer.bridgeName),
        ]
      : const <SetupStep>[];

  final incomplete = steps.any((s) => !s.done);
  final presenceStatus = _presenceStatus(trainer.presence);
  final status = incomplete && presenceStatus == LinkStatus.ready ? LinkStatus.attention : presenceStatus;

  return ChainLink(
    key: ChainLinkKey.trainer,
    id: 'trainer',
    status: status,
    title: trainer.name,
    optional: true,
    steps: steps,
    subtitleArg: status == LinkStatus.ready ? trainer.metrics : null,
    deviceId: trainer.deviceId,
    dismissible: !paired && trainer.presence != DevicePresence.resetting,
  );
}

ChainLink _appLink(ChainInputs inputs) {
  final app = inputs.app;
  final selected = app.name != null;
  // A self-hosted app (BikeControl running the workout itself) has no wire to
  // check: both connection steps are satisfied by definition.
  final hasMethod = app.selfHosted || app.hasEnabledConnection;
  final connected = app.selfHosted || app.isConnected;

  final steps = <SetupStep>[
    SetupStep(id: SetupStepId.appSelected, done: selected),
    SetupStep(id: SetupStepId.appConnectionMethod, done: selected && hasMethod),
    SetupStep(id: SetupStepId.appConnected, done: selected && connected),
  ];

  final LinkStatus status;
  if (steps.every((s) => s.done)) {
    status = LinkStatus.ready;
  } else if (!selected) {
    status = LinkStatus.off;
  } else if (app.wasConnectedThisSession && !app.isConnected) {
    // It was carrying commands a moment ago and stopped — that is a break, not
    // an unfinished setup.
    status = LinkStatus.problem;
  } else {
    status = LinkStatus.attention;
  }

  return ChainLink(
    key: ChainLinkKey.app,
    id: 'app',
    status: status,
    title: app.name ?? '',
    steps: steps,
    subtitleArg: status == LinkStatus.ready ? app.connectionSummary : null,
  );
}
