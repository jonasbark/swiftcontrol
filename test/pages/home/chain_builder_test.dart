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
}) {
  return ControllerInput(
    deviceId: deviceId,
    name: name,
    presence: presence,
    hasMappedButtons: hasMappedButtons,
    requiresBluetooth: requiresBluetooth,
  );
}

TrainerInput trainer({
  DevicePresence presence = DevicePresence.connected,
  bool gearsConfigured = true,
}) {
  return TrainerInput(
    deviceId: 'trainer-1',
    name: 'Wahoo KICKR CORE',
    presence: presence,
    gearsConfigured: gearsConfigured,
    gearsSummary: '24 gears · ratio 2.40',
    metrics: '250 W · 90 rpm',
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

    test('a connected trainer with gears set up is ready and shows its metrics', () {
      final chain = buildChain(ChainInputs(controllers: [controller()], trainer: trainer(), app: _readyApp));
      final link = chain.byKey(ChainLinkKey.trainer);
      expect(link.status, LinkStatus.ready);
      expect(link.subtitleArg, '250 W · 90 rpm');
    });

    test('metrics are withheld unless the trainer is actually ready', () {
      final chain = buildChain(
        ChainInputs(trainer: trainer(presence: DevicePresence.remembered), app: _readyApp),
      );
      expect(chain.byKey(ChainLinkKey.trainer).subtitleArg, isNull);
    });

    test('a connected trainer without gears is amber, with gears as the active step', () {
      final chain = buildChain(ChainInputs(trainer: trainer(gearsConfigured: false), app: _readyApp));
      final link = chain.byKey(ChainLinkKey.trainer);
      expect(link.status, LinkStatus.attention);
      expect(link.activeStep!.id, SetupStepId.trainerGears);
    });

    test('the gears hint carries the configured summary', () {
      final chain = buildChain(ChainInputs(trainer: trainer(), app: _readyApp));
      final step = chain.byKey(ChainLinkKey.trainer).steps.firstWhere((s) => s.id == SetupStepId.trainerGears);
      expect(step.hintArg, '24 gears · ratio 2.40');
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
