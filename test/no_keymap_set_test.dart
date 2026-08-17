import 'package:bike_control/bluetooth/devices/base_device.dart';
import 'package:bike_control/bluetooth/messages/notification.dart';
import 'package:bike_control/gen/l10n.dart';
import 'package:bike_control/utils/actions/android.dart';
import 'package:bike_control/utils/actions/base_actions.dart';
import 'package:bike_control/utils/actions/desktop.dart';
import 'package:bike_control/utils/actions/remote.dart';
import 'package:bike_control/utils/core.dart';
import 'package:bike_control/utils/keymap/buttons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Regression coverage for the "Null check operator used on a null value"
/// crash on every button press: the keymap pref ('app') can be absent while a
/// trainer app ('trainer_app') is selected, leaving `supportedApp` null. Every
/// action handler used to dereference it with `!`, and the device layer used to
/// silently drop its buttons, so no button ever showed up for editing either.
Future<void> main() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  await AppLocalizations.load(const Locale('en'));

  const button = ControllerButton('shifterA');

  final activeDevices = <BaseDevice>[];

  setUp(() {
    // A handler with NO keymap resolved — the real user's state.
    core.actionHandler = StubActions()..supportedApp = null;
  });

  tearDown(() async {
    for (final device in activeDevices) {
      await device.disconnect();
    }
    activeDevices.clear();
  });

  group('performAction with no keymap set', () {
    test('RemoteActions reports noKeymapSet instead of throwing', () async {
      final actions = RemoteActions()..supportedApp = null;

      final result = await actions.performAction(button, isKeyDown: true, isKeyUp: true);

      expect(result, isA<Error>());
      expect((result as Error).type, ErrorType.noKeymapSet);
      expect(result.message, isNotEmpty);
    });

    test('DesktopActions reports noKeymapSet instead of throwing', () async {
      final actions = DesktopActions()..supportedApp = null;

      final result = await actions.performAction(button, isKeyDown: true, isKeyUp: true);

      expect(result, isA<Error>());
      expect((result as Error).type, ErrorType.noKeymapSet);
    });

    test('AndroidActions reports noKeymapSet instead of throwing', () async {
      final actions = AndroidActions()..supportedApp = null;

      final result = await actions.performAction(button, isKeyDown: true, isKeyUp: true);

      expect(result, isA<Error>());
      expect((result as Error).type, ErrorType.noKeymapSet);
    });
  });

  group('BaseDevice with no keymap set', () {
    test('getOrAddButton still registers the button on the device', () {
      final device = _TestDevice();
      activeDevices.add(device);

      expect(core.actionHandler.supportedApp, isNull);
      expect(device.availableButtons, isEmpty);

      final created = device.getOrAddButton('shifterA', () => button);

      expect(created.name, button.name);
      expect(
        device.availableButtons.map((e) => e.name),
        contains(button.name),
        reason: 'a device without a keymap must still expose its buttons for editing',
      );
    });

    test('getOrAddButton does not duplicate a button it already knows', () {
      final device = _TestDevice();
      activeDevices.add(device);

      device.getOrAddButton('shifterA', () => button);
      device.getOrAddButton('shifterA', () => button);

      expect(device.availableButtons.where((e) => e.name == button.name).length, 1);
    });

    test('a press does not log "Error handling button clicks"', () async {
      final device = _TestDevice();
      activeDevices.add(device);
      device.getOrAddButton('shifterA', () => button);

      final logs = <String>[];
      final sub = device.actionStream.listen((n) {
        if (n is LogNotification) logs.add(n.message);
      });

      await device.handleButtonsClicked([button]);
      await device.handleButtonsClicked([]);
      await Future<void>.delayed(const Duration(milliseconds: 600));
      await sub.cancel();

      expect(
        logs.where((m) => m.contains('Error handling button clicks')),
        isEmpty,
        reason: 'a missing keymap must not blow up the button-click handler',
      );
      expect(device.availableButtons, isNotEmpty);
    });
  });
}

class _TestDevice extends BaseDevice {
  _TestDevice()
    : super(
        'NoKeymapTestDevice',
        uniqueId: 'no-keymap-test-device',
        availableButtons: [],
        icon: Icons.gamepad,
      );

  @override
  Future<void> connect() async {}
}
