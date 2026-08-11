import 'package:bike_control/pages/home/chain_builder.dart';
import 'package:bike_control/pages/home/chain_inputs.dart';
import 'package:bike_control/pages/home/chain_state.dart';
import 'package:flutter_test/flutter_test.dart';

const _readyApp = AppInput(
  name: 'MyWhoosh',
  hasEnabledConnection: true,
  isConnected: true,
  wasConnectedThisSession: true,
  connectionSummary: 'Network',
);

ControllerInput controller({
  String deviceId = 'aa:bb',
  String name = 'Zwift Click V2',
  DevicePresence presence = DevicePresence.connected,
  bool hasMappedButtons = true,
  bool requiresBluetooth = true,
  bool? unlocked,
  String? unlockedUntil,
  bool unlockUncertain = false,
  bool? sramSetupDone,
}) {
  return ControllerInput(
    deviceId: deviceId,
    name: name,
    presence: presence,
    hasMappedButtons: hasMappedButtons,
    requiresBluetooth: requiresBluetooth,
    unlocked: unlocked,
    unlockedUntil: unlockedUntil,
    unlockUncertain: unlockUncertain,
    sramSetupDone: sramSetupDone,
  );
}

TrainerInput trainer({
  DevicePresence presence = DevicePresence.connected,
  bool appHoldsBridge = true,
  String? metrics = '250 W · 90 rpm',
}) {
  return TrainerInput(
    deviceId: 'trainer-1',
    name: 'Wahoo KICKR CORE',
    presence: presence,
    appHoldsBridge: appHoldsBridge,
    bridgeName: 'KICKR CORE - BikeControl',
    metrics: metrics,
  );
}

extension on List<ChainLink> {
  ChainLink byKey(ChainLinkKey key) => firstWhere((l) => l.key == key);
  Iterable<ChainLink> allOf(ChainLinkKey key) => where((l) => l.key == key);
}

bool _stepDone(ChainLink link, SetupStepId id) => link.steps.firstWhere((s) => s.id == id).done;

bool _hasStep(ChainLink link, SetupStepId id) => link.steps.any((s) => s.id == id);

void main() {
  group('chain shape', () {
    test('renders controller, trainer then app in signal-path order', () {
      final chain = buildChain(ChainInputs(controllers: [controller()], trainer: trainer(), app: _readyApp));
      expect(chain.map((l) => l.key), [ChainLinkKey.controller, ChainLinkKey.trainer, ChainLinkKey.app]);
    });

    test('renders one card per controller, each with its own id', () {
      final chain = buildChain(
        ChainInputs(
          controllers: [controller(deviceId: 'left'), controller(deviceId: 'right')],
          app: _readyApp,
        ),
      );
      final controllers = chain.allOf(ChainLinkKey.controller).toList();
      expect(controllers, hasLength(2));
      expect(controllers.map((l) => l.id), ['controller:left', 'controller:right']);
    });
  });

  group('controller steps', () {
    test('a connected, mapped controller is ready with every step done', () {
      final chain = buildChain(ChainInputs(controllers: [controller()], app: _readyApp));
      final link = chain.byKey(ChainLinkKey.controller);
      expect(link.status, LinkStatus.ready);
      expect(link.remainingSteps, 0);
      expect(link.activeStepIndex, isNull);
      expect(_stepDone(link, SetupStepId.controllerInRange), isTrue);
    });

    // Zwift locks the Click V2 to their own app and it stops sending presses a
    // minute later, which is indistinguishable from a flat battery unless the
    // chain says so. Every other controller must not grow a line it can never
    // tick.
    test('a locked controller carries an outstanding unlock step', () {
      final chain = buildChain(ChainInputs(controllers: [controller(unlocked: false)], app: _readyApp));
      final link = chain.byKey(ChainLinkKey.controller);
      expect(_stepDone(link, SetupStepId.controllerUnlocked), isFalse);
      // And it is the thing to do next: everything before it is already done.
      expect(link.activeStep?.id, SetupStepId.controllerUnlocked);
      // A card with work outstanding is never green.
      expect(link.status, LinkStatus.attention);
    });

    test('an unlocked controller ticks the step and stays ready', () {
      final chain = buildChain(ChainInputs(controllers: [controller(unlocked: true)], app: _readyApp));
      final link = chain.byKey(ChainLinkKey.controller);
      expect(_stepDone(link, SetupStepId.controllerUnlocked), isTrue);
      expect(link.remainingSteps, 0);
      expect(link.status, LinkStatus.ready);
    });

    // Deliberately the one done step that carries detail: an unlock expires, so
    // a bare tick would hide that it comes back tomorrow.
    test('a finished unlock step carries its deadline and its certainty', () {
      final chain = buildChain(
        ChainInputs(
          controllers: [controller(unlocked: true, unlockedUntil: 'Friday, 14:30', unlockUncertain: true)],
          app: _readyApp,
        ),
      );
      final step = chain.byKey(ChainLinkKey.controller).steps.firstWhere(
        (s) => s.id == SetupStepId.controllerUnlocked,
      );
      expect(step.done, isTrue);
      expect(step.hintArg, 'Friday, 14:30');
      // BikeControl cannot read the lock state back, so "unlocked" is a guess
      // and the label has to say so.
      expect(step.uncertain, isTrue);
    });

    test('a confirmed unlock is not marked uncertain', () {
      final chain = buildChain(
        ChainInputs(
          controllers: [controller(unlocked: true, unlockedUntil: 'Friday, 14:30')],
          app: _readyApp,
        ),
      );
      final step = chain.byKey(ChainLinkKey.controller).steps.firstWhere(
        (s) => s.id == SetupStepId.controllerUnlocked,
      );
      expect(step.uncertain, isFalse);
    });

    // A SRAM derailleur whose own shifting is still enabled is connected and
    // sends nothing at all — the card used to show that as a bare empty panel.
    test('a SRAM derailleur awaiting its guided setup carries that step', () {
      final chain = buildChain(ChainInputs(controllers: [controller(sramSetupDone: false)], app: _readyApp));
      final link = chain.byKey(ChainLinkKey.controller);
      expect(_stepDone(link, SetupStepId.controllerSramSetup), isFalse);
      expect(link.activeStep?.id, SetupStepId.controllerSramSetup);
      expect(link.status, LinkStatus.attention);
    });

    test('a finished SRAM setup ticks and leaves the card ready', () {
      final chain = buildChain(ChainInputs(controllers: [controller(sramSetupDone: true)], app: _readyApp));
      final link = chain.byKey(ChainLinkKey.controller);
      expect(_stepDone(link, SetupStepId.controllerSramSetup), isTrue);
      expect(link.remainingSteps, 0);
      expect(link.status, LinkStatus.ready);
    });

    // It outranks the unlock step: a derailleur that sends nothing cannot be
    // helped by anything further down the list.
    test('guided setup comes before the unlock step', () {
      final chain = buildChain(
        ChainInputs(controllers: [controller(sramSetupDone: false, unlocked: false)], app: _readyApp),
      );
      final link = chain.byKey(ChainLinkKey.controller);
      expect(link.activeStep?.id, SetupStepId.controllerSramSetup);
    });

    test('a controller with no guided setup has no such step', () {
      final chain = buildChain(ChainInputs(controllers: [controller()], app: _readyApp));
      final link = chain.byKey(ChainLinkKey.controller);
      expect(link.steps.any((s) => s.id == SetupStepId.controllerSramSetup), isFalse);
    });

    test('a controller with no unlock concept has no unlock step at all', () {
      final chain = buildChain(ChainInputs(controllers: [controller()], app: _readyApp));
      final link = chain.byKey(ChainLinkKey.controller);
      expect(link.steps.any((s) => s.id == SetupStepId.controllerUnlocked), isFalse);
    });

    test('pairing stays ticked while the device is away — it is history', () {
      final chain = buildChain(
        ChainInputs(controllers: [controller(presence: DevicePresence.remembered)], app: _readyApp),
      );
      final link = chain.byKey(ChainLinkKey.controller);
      expect(_stepDone(link, SetupStepId.controllerPaired), isTrue);
      expect(_stepDone(link, SetupStepId.controllerInRange), isFalse);
    });

    test('a remembered controller is amber, not red, on a fresh launch', () {
      final chain = buildChain(
        ChainInputs(controllers: [controller(presence: DevicePresence.remembered)], app: _readyApp),
      );
      expect(chain.byKey(ChainLinkKey.controller).status, LinkStatus.attention);
    });

    test('a controller that dropped this session is red', () {
      final chain = buildChain(
        ChainInputs(controllers: [controller(presence: DevicePresence.lost)], app: _readyApp),
      );
      expect(chain.byKey(ChainLinkKey.controller).status, LinkStatus.problem);
    });

    test('a controller we have only discovered has not been paired yet', () {
      final chain = buildChain(
        ChainInputs(controllers: [controller(presence: DevicePresence.discovered)], app: _readyApp),
      );
      final link = chain.byKey(ChainLinkKey.controller);
      expect(_stepDone(link, SetupStepId.controllerPaired), isFalse);
      expect(link.status, LinkStatus.off);
    });

    test('a resetting controller is amber and never red', () {
      final chain = buildChain(
        ChainInputs(controllers: [controller(presence: DevicePresence.resetting)], app: _readyApp),
      );
      expect(chain.byKey(ChainLinkKey.controller).status, LinkStatus.attention);
    });

    test('a connected controller with no buttons mapped is not green', () {
      final chain = buildChain(
        ChainInputs(controllers: [controller(hasMappedButtons: false)], app: _readyApp),
      );
      final link = chain.byKey(ChainLinkKey.controller);
      expect(link.status, LinkStatus.attention);
      expect(link.activeStep!.id, SetupStepId.controllerButtonsMapped);
    });

    test('Bluetooth being off leaves the first step as the active one', () {
      final chain = buildChain(
        ChainInputs(bluetoothReady: false, controllers: [controller()], app: _readyApp),
      );
      final link = chain.byKey(ChainLinkKey.controller);
      expect(link.activeStep!.id, SetupStepId.controllerBluetoothReady);
      expect(link.status, LinkStatus.attention);
    });

    test('a non-Bluetooth controller has no Bluetooth step at all', () {
      final chain = buildChain(
        ChainInputs(
          bluetoothReady: false,
          controllers: [controller(requiresBluetooth: false)],
          app: _readyApp,
        ),
      );
      final link = chain.byKey(ChainLinkKey.controller);
      expect(_hasStep(link, SetupStepId.controllerBluetoothReady), isFalse);
      expect(link.status, LinkStatus.ready);
    });

    test('no controller at all renders one grey placeholder, not an empty screen', () {
      final chain = buildChain(const ChainInputs(app: _readyApp));
      final controllers = chain.allOf(ChainLinkKey.controller).toList();
      expect(controllers, hasLength(1));
      expect(controllers.single.status, LinkStatus.off);
      expect(controllers.single.id, 'controller');
      expect(controllers.single.deviceId, isNull);
      expect(_stepDone(controllers.single, SetupStepId.controllerPaired), isFalse);
    });
  });

  group('swipe-away eligibility', () {
    test('a connected controller cannot be swiped away', () {
      final chain = buildChain(ChainInputs(controllers: [controller()], app: _readyApp));
      expect(chain.byKey(ChainLinkKey.controller).dismissible, isFalse);
    });

    test('remembered and lost controllers can be swiped away', () {
      for (final presence in [DevicePresence.remembered, DevicePresence.lost]) {
        final chain = buildChain(
          ChainInputs(controllers: [controller(presence: presence)], app: _readyApp),
        );
        expect(chain.byKey(ChainLinkKey.controller).dismissible, isTrue, reason: presence.name);
      }
    });

    test('a resetting controller cannot be swiped away — it is coming back', () {
      final chain = buildChain(
        ChainInputs(controllers: [controller(presence: DevicePresence.resetting)], app: _readyApp),
      );
      expect(chain.byKey(ChainLinkKey.controller).dismissible, isFalse);
    });

    test('the placeholder card is not dismissible', () {
      final chain = buildChain(const ChainInputs(app: _readyApp));
      expect(chain.byKey(ChainLinkKey.controller).dismissible, isFalse);
    });
  });

  group('trainer link', () {
    test('is optional and, with no trainer known, has no checklist', () {
      final chain = buildChain(const ChainInputs(app: _readyApp));
      final link = chain.byKey(ChainLinkKey.trainer);
      expect(link.optional, isTrue);
      expect(link.status, LinkStatus.off);
      expect(link.steps, isEmpty);
      expect(link.isBlocking, isFalse);
    });

    test('a trainer we have only discovered offers no checklist', () {
      final chain = buildChain(
        ChainInputs(trainer: trainer(presence: DevicePresence.discovered), app: _readyApp),
      );
      // Unticked boxes on a trainer nobody has committed to read as work
      // outstanding when there is none.
      expect(chain.byKey(ChainLinkKey.trainer).steps, isEmpty);
    });

    test('a remembered trainer left disconnected offers no checklist either', () {
      final chain = buildChain(
        ChainInputs(trainer: trainer(presence: DevicePresence.remembered), app: _readyApp),
      );
      expect(chain.byKey(ChainLinkKey.trainer).steps, isEmpty);
    });

    test('a trainer that dropped keeps its checklist', () {
      final chain = buildChain(ChainInputs(trainer: trainer(presence: DevicePresence.lost), app: _readyApp));
      expect(chain.byKey(ChainLinkKey.trainer).steps, isNotEmpty);
    });

    test('a connected trainer with gears set up is ready and shows its metrics', () {
      final chain = buildChain(ChainInputs(controllers: [controller()], trainer: trainer(), app: _readyApp));
      final link = chain.byKey(ChainLinkKey.trainer);
      expect(link.status, LinkStatus.ready);
      expect(link.subtitleArg, '250 W · 90 rpm');
    });

    // The numbers come off the trainer, not off the bridge: a trainer that is
    // reporting watts is reporting watts whether or not the app has picked the
    // bridge up, and hiding them until the whole link is green would withhold
    // something both true and useful.
    test('live values show even while the app has not picked the bridge up', () {
      final chain = buildChain(ChainInputs(trainer: trainer(appHoldsBridge: false), app: _readyApp));
      final link = chain.byKey(ChainLinkKey.trainer);
      expect(link.status, LinkStatus.attention);
      expect(link.subtitleArg, '250 W · 90 rpm');
    });

    test('a trainer reporting nothing shows no readout', () {
      final chain = buildChain(
        ChainInputs(trainer: trainer(presence: DevicePresence.remembered, metrics: null), app: _readyApp),
      );
      expect(chain.byKey(ChainLinkKey.trainer).subtitleArg, isNull);
    });

    // The bug this pins down: a trainer the scanner had only just found was
    // reported as having lost a connection it never had.
    // Regression: a remembered trainer mapped to amber, which on an optional
    // card blocks "Ready to ride" — and made the card present itself as
    // bridged when it was not even in the room.
    test('a remembered trainer rests at off and does not block the rider', () {
      final chain = buildChain(
        ChainInputs(
          controllers: [controller()],
          trainer: trainer(presence: DevicePresence.remembered, appHoldsBridge: false),
          app: _readyApp,
        ),
      );
      final link = chain.byKey(ChainLinkKey.trainer);
      expect(link.status, LinkStatus.off);
      expect(link.isBlocking, isFalse);
      expect(deriveBanner(chain).kind, ChainBannerKind.ready);
    });

    test('a trainer we have only discovered is not reported as broken', () {
      final chain = buildChain(
        ChainInputs(trainer: trainer(presence: DevicePresence.discovered), app: _readyApp),
      );
      final link = chain.byKey(ChainLinkKey.trainer);
      expect(link.status, isNot(LinkStatus.problem));
      expect(link.status, LinkStatus.off);
    });

    test('a newly discovered trainer does not stop the rider being ready', () {
      final chain = buildChain(
        ChainInputs(
          controllers: [controller()],
          trainer: trainer(presence: DevicePresence.discovered),
          app: _readyApp,
        ),
      );
      expect(chain.byKey(ChainLinkKey.trainer).isBlocking, isFalse);
      expect(deriveBanner(chain).kind, ChainBannerKind.ready);
    });

    test('a trainer that actually dropped is still reported as broken', () {
      final chain = buildChain(ChainInputs(trainer: trainer(presence: DevicePresence.lost), app: _readyApp));
      expect(chain.byKey(ChainLinkKey.trainer).status, LinkStatus.problem);
    });

    // Onboarding is the source of truth: a bridge the trainer app hasn't picked
    // up yet is honest about it rather than claiming to be bridged.
    test('a bridged trainer the app has not picked up is amber, not ready', () {
      final chain = buildChain(ChainInputs(trainer: trainer(appHoldsBridge: false), app: _readyApp));
      final link = chain.byKey(ChainLinkKey.trainer);
      expect(link.status, LinkStatus.attention);
      expect(link.activeStep!.id, SetupStepId.trainerAppBridged);
    });

    test('the pick-up step names the bridge to look for', () {
      final chain = buildChain(ChainInputs(trainer: trainer(), app: _readyApp));
      final step = chain.byKey(ChainLinkKey.trainer).steps.firstWhere((s) => s.id == SetupStepId.trainerAppBridged);
      expect(step.hintArg, 'KICKR CORE - BikeControl');
    });

    test('gear ratios are a preference, never a setup step', () {
      final chain = buildChain(ChainInputs(trainer: trainer(), app: _readyApp));
      expect(
        chain.byKey(ChainLinkKey.trainer).steps.map((s) => s.id),
        [SetupStepId.trainerPaired, SetupStepId.trainerAppBridged],
      );
    });
  });

  group('app link', () {
    test('is ready when selected, wired and connected', () {
      final chain = buildChain(ChainInputs(controllers: [controller()], app: _readyApp));
      final link = chain.byKey(ChainLinkKey.app);
      expect(link.status, LinkStatus.ready);
      expect(link.subtitleArg, 'Network');
    });

    test('no app selected is grey, with selection as the active step', () {
      final chain = buildChain(const ChainInputs());
      final link = chain.byKey(ChainLinkKey.app);
      expect(link.status, LinkStatus.off);
      expect(link.activeStep!.id, SetupStepId.appSelected);
    });

    test('later steps stay pending while no app is selected', () {
      final chain = buildChain(const ChainInputs(app: AppInput(hasEnabledConnection: true, isConnected: true)));
      final link = chain.byKey(ChainLinkKey.app);
      expect(_stepDone(link, SetupStepId.appConnectionMethod), isFalse);
      expect(_stepDone(link, SetupStepId.appConnected), isFalse);
    });

    test('selected but with no connection method is amber', () {
      final chain = buildChain(const ChainInputs(app: AppInput(name: 'MyWhoosh')));
      final link = chain.byKey(ChainLinkKey.app);
      expect(link.status, LinkStatus.attention);
      expect(link.activeStep!.id, SetupStepId.appConnectionMethod);
    });

    test('an app that was connected and dropped is red', () {
      final chain = buildChain(
        const ChainInputs(
          app: AppInput(name: 'MyWhoosh', hasEnabledConnection: true, wasConnectedThisSession: true),
        ),
      );
      expect(chain.byKey(ChainLinkKey.app).status, LinkStatus.problem);
    });

    test('an app that has never connected is amber, not red', () {
      final chain = buildChain(const ChainInputs(app: AppInput(name: 'MyWhoosh', hasEnabledConnection: true)));
      expect(chain.byKey(ChainLinkKey.app).status, LinkStatus.attention);
    });

    test('a self-hosted app needs no connection method and is ready on selection', () {
      final chain = buildChain(const ChainInputs(app: AppInput(name: 'BikeControl', selfHosted: true)));
      final link = chain.byKey(ChainLinkKey.app);
      expect(link.status, LinkStatus.ready);
      expect(link.remainingSteps, 0);
    });
  });

  group('end to end with the banner', () {
    test('the everyday case: ready to ride', () {
      final chain = buildChain(ChainInputs(controllers: [controller()], trainer: trainer(), app: _readyApp));
      expect(deriveBanner(chain).kind, ChainBannerKind.ready);
    });

    test('no trainer paired is still ready to ride', () {
      final chain = buildChain(ChainInputs(controllers: [controller()], app: _readyApp));
      expect(deriveBanner(chain).kind, ChainBannerKind.ready);
    });

    test('a lost controller points the banner at that exact card', () {
      final chain = buildChain(
        ChainInputs(
          controllers: [controller(deviceId: 'left'), controller(deviceId: 'right', presence: DevicePresence.lost)],
          app: _readyApp,
        ),
      );
      final banner = deriveBanner(chain);
      expect(banner.kind, ChainBannerKind.broken);
      expect(banner.targetLinkId, 'controller:right');
    });

    test('fresh install counts every outstanding step across both cards', () {
      final chain = buildChain(const ChainInputs());
      final banner = deriveBanner(chain);
      expect(banner.kind, ChainBannerKind.pending);
      // Controller placeholder: paired + mapped. App: selected + method + connected.
      expect(banner.stepsLeft, 5);
      expect(banner.targetLinkId, 'controller');
      expect(banner.outstandingKeys, [ChainLinkKey.controller, ChainLinkKey.app]);
    });
  });
}
