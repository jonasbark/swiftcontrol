import 'package:bike_control/bluetooth/devices/gyroscope/gyroscope_steering.dart';
import 'package:bike_control/gen/l10n.dart';
import 'package:bike_control/utils/actions/base_actions.dart';
import 'package:bike_control/utils/core.dart';
import 'package:bike_control/utils/iap/iap_manager.dart';
import 'package:bike_control/utils/keymap/apps/zwift.dart';
import 'package:bike_control/utils/keymap/buttons.dart';
import 'package:bike_control/utils/keymap/keymap.dart';
import 'package:flutter_test/flutter_test.dart';

import 'harness/test_env.dart';

class _TestActions extends BaseActions {
  _TestActions() : super(supportedModes: const []);
  @override
  void cleanup() {}
}

Future<void> main() async {
  final env = await IntegrationEnv.setUp();
  late _TestActions actions;

  const button = ControllerButton('calibrateTestBtn');

  setUp(() async {
    await env.resetState();
    core.connection.devices.clear();
    IAPManager.instance.setProForTesting(enabled: true);

    final app = Zwift();
    app.keymap.keyPairs.add(
      KeyPair(
        buttons: const [button],
        physicalKey: null,
        logicalKey: null,
        inGameAction: InGameAction.calibratePhoneSteering,
      ),
    );
    actions = _TestActions()..supportedApp = app;
    core.actionHandler = actions;
  });

  test('key-down recalibrates the connected phone-steering device', () async {
    final device = GyroscopeSteering();
    device.isCalibratedNotifier.value = true; // pretend already calibrated
    core.connection.devices.add(device);

    final result = await actions.performAction(button, isKeyDown: true, isKeyUp: false);

    expect(result, isA<Success>());
    expect(result.message, AppLocalizations.current.steeringRecalibrating);
    expect(device.isCalibratedNotifier.value, isFalse); // recalibrate() ran
  });

  test('key-up is ignored (no double trigger)', () async {
    core.connection.devices.add(GyroscopeSteering());
    final result = await actions.performAction(button, isKeyDown: false, isKeyUp: true);
    expect(result, isA<Ignored>());
  });

  test('no phone-steering device ⇒ Ignored not-enabled', () async {
    final result = await actions.performAction(button, isKeyDown: true, isKeyUp: false);
    expect(result, isA<Ignored>());
    expect(result.message, AppLocalizations.current.phoneSteeringNotEnabled);
  });
}
