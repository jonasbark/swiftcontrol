@Tags(['screenshots'])
library;

import 'package:bike_control/bluetooth/devices/zwift/constants.dart';
import 'package:bike_control/bluetooth/devices/zwift/zwift_click.dart';
import 'package:bike_control/main.dart' show screenshotMode;
import 'package:bike_control/pages/button_edit.dart';
import 'package:bike_control/pages/configuration.dart';
import 'package:bike_control/utils/actions/base_actions.dart' show StubActions, SupportedMode;
import 'package:bike_control/utils/core.dart' show core;
import 'package:bike_control/utils/keymap/apps/custom_app.dart';
import 'package:bike_control/utils/keymap/apps/my_whoosh.dart';
import 'package:bike_control/utils/keymap/buttons.dart';
import 'package:bike_control/utils/keymap/keymap.dart';
import 'package:bike_control/utils/requirements/multi.dart' show KeyboardRequirement, Target;
import 'package:bike_control/widgets/apps/local_tile.dart';
import 'package:bike_control/widgets/custom_keymap_selector.dart';
import 'package:bike_control/widgets/keymap_explanation.dart';
import 'package:bike_control/widgets/ui/permissions_list.dart';
import 'package:flutter/foundation.dart' show TargetPlatform, debugDefaultTargetPlatformOverride;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:universal_ble/universal_ble.dart';

import 'widget_snapshot.dart';

/// Snapshots the Local connection method for the tutorial
/// "Get the Most Out of BikeControl with the Local Connection Method":
/// the target picker, the Local tile, the keyboard-permission sheet, the button
/// editor with a keyboard shortcut and with a mouse click assigned, the
/// press-a-key dialog, and the resulting mapping table.
///
/// These are the desktop renders (keyboard + mouse + media) — the host is macOS,
/// so `Platform.isMacOS` is true, and each capture also overrides the
/// framework's target platform to macOS so no Android-only card sneaks in.
///
/// Run: `flutter test --run-skipped test/local_connection_snapshot_test.dart`
Future<void> main() async {
  await ensureSnapshotHarness();

  // The tutorial needs the real product names and the real permission rows, not
  // the anonymized marketing variants the store boards use.
  screenshotMode = false;

  // Local on desktop simulates keyboard, mouse and media keys — mirror
  // DesktopActions' supportedModes so every card the real app shows is shown.
  core.actionHandler = StubActions(
    supportedModes: const [SupportedMode.keyboard, SupportedMode.touch, SupportedMode.media],
  );

  // macOS asks the OS for keyboard access; report it granted so the tiles render
  // in their "ready" state instead of nagging.
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
    const MethodChannel('dev.leanflutter.plugins/keypress_simulator'),
    (call) async => true,
  );

  final app = MyWhoosh();
  final click = ZwiftClick(BleDevice(name: 'Zwift Click', deviceId: '00:11:22:33:44:55'))
    ..firmwareVersion = '1.1.0'
    ..isConnected = true
    ..rssi = -51
    ..batteryLevel = 81;

  // Devices first: actionHandler.init seeds the keymap from every connected
  // controller's buttons, which is what gives the mapping table its rows.
  core.connection.addDevices([click]);
  core.actionHandler.init(app);

  core.settings.setTrainerApp(app);
  await core.settings.setLastTarget(Target.thisDevice);
  core.settings.setLocalEnabled(true);
  core.local.isStarted.value = true;
  core.local.isConnected.value = true;

  const shiftUp = ZwiftButtons.shiftUpRight;
  const shiftDown = ZwiftButtons.shiftUpLeft;

  KeyPair pairFor(ControllerButton button) =>
      app.keymap.getOrCreateKeyPair(button, trigger: ButtonTrigger.singleClick);

  /// Renders [body] with the framework's target platform pinned to macOS. The
  /// flag is reset inside the test body, not in a tearDown: the binding checks
  /// "no debug variable was changed" before tearDowns run.
  Future<void> asMacOS(Future<void> Function() body) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      await body();
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  }

  testWidgets('Step 1 — trainer app + "This Device" target', (tester) async {
    await asMacOS(
      () => captureWidget(
        tester,
        name: '01_target_this_device',
        width: 430,
        builder: (context) => ConfigurationPage(onUpdate: () {}, onboardingMode: true),
      ),
    );
  });

  testWidgets('Step 2 — the Local connection tile', (tester) async {
    await asMacOS(
      () => captureWidget(
        tester,
        name: '02_local_tile',
        width: 420,
        builder: (context) => LocalTile(small: false),
      ),
    );
  });

  testWidgets('Step 3 — the permission sheet Local opens', (tester) async {
    await asMacOS(
      () => captureWidget(
        tester,
        name: '03_keyboard_permission',
        width: 400,
        builder: (context) => PermissionList(requirements: [KeyboardRequirement()], onDone: () {}),
      ),
    );
  });

  testWidgets('Step 4 — the predefined MyWhoosh keymap', (tester) async {
    await asMacOS(
      () => captureWidget(
        tester,
        name: '04_mapping_predefined',
        width: 420,
        builder: (context) => KeymapExplanation(keymap: app.keymap, filterDevice: click, onUpdate: () {}),
      ),
    );
  });

  testWidgets('Step 5 — button editor with a keyboard shortcut', (tester) async {
    final keyPair = pairFor(shiftUp)
      ..physicalKey = PhysicalKeyboardKey.arrowUp
      ..logicalKey = LogicalKeyboardKey.arrowUp
      ..modifiers = []
      ..touchPosition = Offset.zero;

    await asMacOS(
      () => captureWidget(
        tester,
        name: '05_button_edit_keyboard',
        width: 320,
        builder: (context) => SizedBox(
          height: 358,
          child: ButtonEditPage(
            keyPair: keyPair,
            device: click,
            keymap: app.keymap,
            trigger: ButtonTrigger.singleClick,
            onUpdate: () {},
          ),
        ),
      ),
    );
  });

  testWidgets('Step 6 — the press-a-key dialog', (tester) async {
    await asMacOS(
      () => captureWidget(
        tester,
        name: '06_press_a_key',
        width: 400,
        builder: (context) => HotKeyListenerDialog(
          customApp: CustomApp(profileName: 'MyWhoosh (Copy)'),
          keyPair: pairFor(shiftUp),
        ),
      ),
    );
  });

  testWidgets('Step 7 — button editor with a mouse click', (tester) async {
    final keyPair = pairFor(shiftDown)
      ..physicalKey = null
      ..logicalKey = null
      ..modifiers = []
      // Touch positions are percentages of the screen (see
      // BaseActions.getTouchPosition), so this is 88% across, 62% down.
      ..touchPosition = const Offset(88, 62);

    await asMacOS(
      () => captureWidget(
        tester,
        name: '07_button_edit_mouse',
        width: 320,
        builder: (context) => SizedBox(
          height: 358,
          child: ButtonEditPage(
            keyPair: keyPair,
            device: click,
            keymap: app.keymap,
            trigger: ButtonTrigger.singleClick,
            onUpdate: () {},
          ),
        ),
      ),
    );
  });

  testWidgets('Step 8 — the mapping table after both edits', (tester) async {
    await asMacOS(
      () => captureWidget(
        tester,
        name: '08_mapping_custom',
        width: 420,
        builder: (context) => KeymapExplanation(keymap: app.keymap, filterDevice: click, onUpdate: () {}),
      ),
    );
  });
}
