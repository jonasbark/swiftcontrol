import 'package:bike_control/bluetooth/devices/zwift/controller_keep_alive.dart' show kZwiftControllerReleasedState;
import 'package:bike_control/bluetooth/devices/zwift/rouvy_mdns_emulator.dart';
import 'package:bike_control/bluetooth/devices/zwift/zwift_ride.dart' show RideButtonMask;
import 'package:bike_control/gen/l10n.dart';
import 'package:bike_control/utils/actions/base_actions.dart';
import 'package:bike_control/utils/core.dart';
import 'package:bike_control/utils/keymap/buttons.dart';
import 'package:bike_control/utils/keymap/keymap.dart';
import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_test/flutter_test.dart';
import 'package:prop/prop.dart' hide RideButtonMask;
import 'package:shared_preferences/shared_preferences.dart';

/// Captures the raw controller frames the Rouvy emulator writes.
class _RecordingClickEmulator extends ClickEmulator {
  final List<List<int>> notifications = [];

  @override
  void writeNotification(List<int> bytes) => notifications.add(List.of(bytes));
}

KeyPair _navPair(InGameAction action) => KeyPair(
  buttons: [ControllerButton('Test', action: action)],
  physicalKey: null,
  logicalKey: null,
  inGameAction: action,
);

int _buttonMapOf(List<int> frame) => RideKeyPadStatus.fromBuffer(frame).buttonMap;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await AppLocalizations.load(const Locale('en'));
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    core.settings.prefs = await SharedPreferences.getInstance();
  });

  group('RouvyMdnsEmulator D-pad navigation', () {
    // The Zwift Ride's raw up/down D-pad buttons default to InGameAction.up /
    // InGameAction.down. Rouvy's keymap has no navigation entries, so those
    // buttons reach the emulator carrying the raw actions — which must map to
    // the physical UP/DOWN buttons rather than falling through to NotHandled
    // (which produced the misleading "Rouvy is not connected" log).
    test('supportedActions includes raw up and down', () {
      final emulator = RouvyMdnsEmulator(clickEmulator: _RecordingClickEmulator());
      expect(emulator.supportedActions, contains(InGameAction.up));
      expect(emulator.supportedActions, contains(InGameAction.down));
    });

    test('InGameAction.up presses UP_BTN and releases on key-up', () async {
      final click = _RecordingClickEmulator();
      final emulator = RouvyMdnsEmulator(clickEmulator: click);

      final down = await emulator.sendAction(_navPair(InGameAction.up), isKeyDown: true, isKeyUp: false);
      expect(down, isA<Success>());
      expect(click.notifications, hasLength(1));
      expect(_buttonMapOf(click.notifications.single), (~RideButtonMask.UP_BTN.mask) & 0xFFFFFFFF);

      final up = await emulator.sendAction(_navPair(InGameAction.up), isKeyDown: false, isKeyUp: true);
      expect(up, isA<Success>());
      expect(click.notifications, hasLength(2));
      expect(click.notifications.last, kZwiftControllerReleasedState);
    });

    test('InGameAction.down presses DOWN_BTN', () async {
      final click = _RecordingClickEmulator();
      final emulator = RouvyMdnsEmulator(clickEmulator: click);

      final result = await emulator.sendAction(_navPair(InGameAction.down), isKeyDown: true, isKeyUp: false);
      expect(result, isA<Success>());
      expect(_buttonMapOf(click.notifications.single), (~RideButtonMask.DOWN_BTN.mask) & 0xFFFFFFFF);
    });
  });
}
