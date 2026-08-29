import 'package:bike_control/utils/actions/remote.dart';
import 'package:bike_control/utils/core.dart';
import 'package:bike_control/utils/keymap/apps/fulgaz.dart';
import 'package:bike_control/utils/keymap/apps/supported_app.dart';
import 'package:bike_control/utils/keymap/apps/tacx.dart';
import 'package:bike_control/utils/requirements/multi.dart';
import 'package:bike_control/utils/trainer_setup.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// FulGaz takes nothing from a controller: decompiling 7.0.6 (Android) and
/// 7.0.9 (macOS) turned up no key handling, no gamepad, no Zwift/OBP service
/// and no mDNS — the app's only trainer transport is Bluetooth. So the one
/// thing BikeControl can be to it is a Bluetooth trainer doing the virtual
/// shifting itself, which is what these expectations pin down.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    core.settings.prefs = await SharedPreferences.getInstance();
    core.actionHandler = RemoteActions();
  });

  test('is offered in the trainer-app chooser', () {
    expect(SupportedApp.supportedApps.whereType<FulGaz>(), hasLength(1));
  });

  test('delivers no button events to the app', () {
    final app = FulGaz();
    // No controller protocol reaches FulGaz, and it reads no keystrokes, so
    // there is nothing to map.
    expect(app.connections, isEmpty);
    expect(app.keymap.keyPairs, isEmpty);
    for (final method in AppConnectionMethod.values) {
      expect(app.supports(method), isFalse, reason: '$method must not be offered for FulGaz');
    }
  });

  test('virtual shifting is Bluetooth-only', () {
    expect(FulGaz().virtualShiftingTransports, {TrainerConnectionType.bluetooth});
  });

  test('accepts no simulated keyboard or pointer input', () {
    expect(FulGaz().acceptsSimulatedInput, isFalse);
  });

  test('cannot run alongside BikeControl on one device', () {
    expect(FulGaz().receivesButtonEvents, isFalse);
    expect(Target.supportedFor(FulGaz()), [Target.otherDevice]);
  });

  test('not picking a connection method is the finished state, not an error', () async {
    await applyTrainerAppSelection(FulGaz());

    // Every tile is hidden for FulGaz, so treating "none enabled" as unfinished
    // setup would disable Continue and strand the rider in onboarding.
    expect(core.logic.hasNoConnectionMethod, isFalse);
  });

  test('selecting FulGaz pins the target to another device', () async {
    await core.settings.setLastTarget(Target.thisDevice);

    await applyTrainerAppSelection(FulGaz());

    expect(core.settings.getLastTarget(), Target.otherDevice);
  });

  test('local and remote-HID methods stay hidden while FulGaz is selected', () async {
    await applyTrainerAppSelection(FulGaz());

    // Both would pair BikeControl as a keyboard/mouse — dead ends for an app
    // that reads neither.
    expect(core.logic.showRemote, isFalse);
    expect(core.logic.showLocalControl, isFalse);
    expect(core.logic.isRemoteControlEnabled, isFalse);
    expect(core.logic.isRemoteKeyboardControlEnabled, isFalse);
  });

  test('every app leaves the rider at least one transport and one target', () {
    // The connection picker indexes into both lists; an app declaring neither
    // would strand the rider on a card with nothing to choose.
    for (final app in SupportedApp.supportedApps) {
      expect(app.virtualShiftingTransports, isNotEmpty, reason: '${app.name} declares no VS transport');
      expect(Target.supportedFor(app), isNotEmpty, reason: '${app.name} declares no usable target');
    }
  });

  test('other trainer apps keep every transport and target', () async {
    // Tacx is the nearest neighbour — also no controller protocol — but it does
    // read keystrokes and does find trainers over the network, so none of the
    // FulGaz restrictions may leak onto it.
    final tacx = Tacx();
    expect(tacx.acceptsSimulatedInput, isTrue);
    expect(tacx.receivesButtonEvents, isTrue);
    expect(tacx.virtualShiftingTransports, {TrainerConnectionType.bluetooth, TrainerConnectionType.wifi});
    expect(Target.supportedFor(tacx), Target.values);

    await applyTrainerAppSelection(tacx);
    await core.settings.setLastTarget(Target.otherDevice);
    expect(core.logic.showRemote, isTrue);
    // Tacx still has to pick one, so the nag must survive.
    expect(core.logic.hasNoConnectionMethod, isTrue);
  });
}
