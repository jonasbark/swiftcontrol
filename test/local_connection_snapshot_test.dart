@Tags(['screenshots'])
library;

import 'package:bike_control/bluetooth/devices/zwift/constants.dart';
import 'package:bike_control/bluetooth/devices/zwift/zwift_click.dart';
import 'package:bike_control/main.dart' show screenshotMode;
import 'package:bike_control/pages/home/chain_builder.dart';
import 'package:bike_control/pages/home/chain_inputs.dart';
import 'package:bike_control/pages/home/chain_state.dart';
import 'package:bike_control/pages/button_edit.dart';
import 'package:bike_control/pages/configuration.dart';
import 'package:bike_control/pages/touch_area.dart';
import 'package:bike_control/utils/actions/android.dart' show AndroidActions;
import 'package:bike_control/utils/actions/base_actions.dart' show BaseActions, StubActions, SupportedMode;
import 'package:bike_control/utils/core.dart' show core;
import 'package:bike_control/utils/i18n_extension.dart';
import 'package:bike_control/utils/keymap/apps/custom_app.dart';
import 'package:bike_control/utils/keymap/apps/my_whoosh.dart';
import 'package:bike_control/utils/keymap/buttons.dart';
import 'package:bike_control/utils/keymap/keymap.dart';
import 'package:bike_control/utils/requirements/multi.dart' show KeyboardRequirement, Target;
import 'package:bike_control/widgets/apps/local_tile.dart';
import 'package:bike_control/widgets/home/chain_card.dart';
import 'package:bike_control/widgets/custom_keymap_selector.dart';
import 'package:bike_control/widgets/keymap_explanation.dart';
import 'package:bike_control/widgets/ui/permissions_list.dart';
import 'package:flutter/foundation.dart' show TargetPlatform, debugDefaultTargetPlatformOverride;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:universal_ble/universal_ble.dart';

import 'dart:io';

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

  // The touch-area editor loads its background from the temp directory and puts
  // the window full-screen. Neither plugin exists under `flutter test`, so:
  //   - no plugin registrant runs under `flutter test`, so path_provider falls
  //     back to its base method channel rather than the macOS implementation —
  //     that is the one to answer;
  //   - window_manager just has to not throw.
  final tempDir = Directory.systemTemp.createTempSync('bikecontrol_snapshots');
  tearDownAll(() => tempDir.deleteSync(recursive: true));
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/path_provider'),
    (call) async => tempDir.path,
  );
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
    const MethodChannel('window_manager'),
    (call) async => null,
  );

  final app = MyWhoosh();
  final click = ZwiftClick(BleDevice(name: 'Zwift Click', deviceId: '00:11:22:33:44:55'))
    ..firmwareVersion = '1.1.0'
    ..isConnected = true
    ..rssi = -51
    ..batteryLevel = 81;

  core.connection.addDevices([click]);
  core.settings.setTrainerApp(app);
  await core.settings.setLastTarget(Target.thisDevice);
  core.settings.setLocalEnabled(true);

  // Devices are added first because init seeds the keymap from every connected
  // controller's buttons, which is what gives the mapping table its rows.
  core.actionHandler.init(app);

  final keymap = app.keymap;

  /// The handler's app gets swapped out from under a long-running test —
  /// registering a button a shipped keymap doesn't have copies that keymap into
  /// a profile of its own, and settings changes re-init the handler from prefs.
  /// Widgets that take a keymap read the one passed in, but the touch-area
  /// editor reads `core.actionHandler.supportedApp.keymap` itself, so the two
  /// have to be the same object. Pin it before every capture.
  void pinApp() => core.actionHandler.supportedApp = app;
  core.local.isStarted.value = true;
  core.local.isConnected.value = true;

  const shiftUp = ZwiftButtons.shiftUpRight;
  const shiftDown = ZwiftButtons.shiftUpLeft;

  KeyPair pairFor(ControllerButton button) =>
      keymap.getOrCreateKeyPair(button, trigger: ButtonTrigger.singleClick);

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

  testWidgets('Step 1 — the trainer app card on the main page', (tester) async {
    pinApp();
    // The genuine card: the chain the home page renders is derived from plain
    // data, so buildChain gives the same link the app would show for "MyWhoosh
    // picked, no connection method switched on yet".
    final link = buildChain(
      const ChainInputs(
        app: AppInput(name: 'MyWhoosh', localControlOffered: true),
      ),
    ).firstWhere((l) => l.key == ChainLinkKey.app);

    await asMacOS(
      () => captureWidget(
        tester,
        name: '01_open_connection_settings',
        width: 420,
        builder: (context) => ChainCard(
          link: link,
          appName: 'MyWhoosh',
          tile: ClipRRect(
            borderRadius: BorderRadius.circular(7),
            child: Image.asset('assets/mywhoosh.png', width: 30, height: 30),
          ),
          title: link.title,
          statusLabel: context.i18n.chainStatusWaitingForApp('MyWhoosh'),
          onEdit: () {},
          onInstructions: () {},
          instructionsLabel: appLinkOpensConnectionSettings(link) ? context.i18n.chainSetUp : null,
        ),
      ),
    );
  });

  testWidgets('Step 2 — trainer app + "This Device" target', (tester) async {
    pinApp();
    await asMacOS(
      () => captureWidget(
        tester,
        name: '02_target_this_device',
        width: 430,
        builder: (context) => ConfigurationPage(onUpdate: () {}, onboardingMode: true),
      ),
    );
  });

  testWidgets('Step 3 — the Local connection tile', (tester) async {
    pinApp();
    await asMacOS(
      () => captureWidget(
        tester,
        name: '03_local_tile',
        width: 420,
        builder: (context) => LocalTile(small: false),
      ),
    );
  });

  testWidgets('Step 4 — the permission sheet Local opens', (tester) async {
    pinApp();
    await asMacOS(
      () => captureWidget(
        tester,
        name: '04_keyboard_permission',
        width: 400,
        builder: (context) => PermissionList(requirements: [KeyboardRequirement()], onDone: () {}),
      ),
    );
  });

  testWidgets('Step 5 — the predefined MyWhoosh keymap', (tester) async {
    pinApp();
    await asMacOS(
      () => captureWidget(
        tester,
        name: '05_mapping_predefined',
        width: 420,
        builder: (context) => KeymapExplanation(keymap: keymap, filterDevice: click, onUpdate: () {}),
      ),
    );
  });

  testWidgets('Step 6 — button editor with a keyboard shortcut', (tester) async {
    pinApp();
    final keyPair = pairFor(shiftUp)
      ..physicalKey = PhysicalKeyboardKey.arrowUp
      ..logicalKey = LogicalKeyboardKey.arrowUp
      ..modifiers = []
      ..touchPosition = Offset.zero;

    await asMacOS(
      () => captureWidget(
        tester,
        name: '06_button_edit_keyboard',
        width: 320,
        builder: (context) => SizedBox(
          height: 358,
          child: ButtonEditPage(
            keyPair: keyPair,
            device: click,
            keymap: keymap,
            trigger: ButtonTrigger.singleClick,
            onUpdate: () {},
          ),
        ),
      ),
    );
  });

  testWidgets('Step 7 — the press-a-key dialog', (tester) async {
    pinApp();
    await asMacOS(
      () => captureWidget(
        tester,
        name: '07_press_a_key',
        width: 400,
        builder: (context) => HotKeyListenerDialog(
          customApp: CustomApp(profileName: 'MyWhoosh (Copy)'),
          keyPair: pairFor(shiftUp),
        ),
      ),
    );
  });

  testWidgets('Step 8 — button editor with a mouse click', (tester) async {
    pinApp();
    final keyPair = pairFor(shiftDown)
      ..physicalKey = null
      ..logicalKey = null
      ..modifiers = []
      // Touch positions are percentages of the screen (see
      // BaseActions.getTouchPosition), so this is 88% across, 62% down.
      // Touch positions are percentages of the screen (see
      // BaseActions.getTouchPosition), and 80/94 is where MyWhoosh draws its
      // on-screen gear-down arrow — the same spot BikeControl's shipped
      // MyWhoosh keymap already points its shift-down click at.
      ..touchPosition = const Offset(80, 94);

    await asMacOS(
      () => captureWidget(
        tester,
        name: '08_button_edit_mouse',
        width: 320,
        builder: (context) => SizedBox(
          height: 358,
          child: ButtonEditPage(
            keyPair: keyPair,
            device: click,
            keymap: keymap,
            trigger: ButtonTrigger.singleClick,
            onUpdate: () {},
          ),
        ),
      ),
    );
  });

  testWidgets('Step 9 — the mouse-position editor over an in-game screenshot', (tester) async {
    pinApp();
    // The editor reads its background from the temp directory, named after the
    // trainer app — the same file _pickScreenshot writes when the rider loads
    // an in-game screenshot.
    File('${tempDir.path}/MyWhoosh_screenshot.png')
        .writeAsBytesSync(File('test/fixtures/mywhoosh_ingame.jpg').readAsBytesSync());

    // The editor draws a target for every key pair that has a touch position,
    // and MyWhoosh's predefined keymap gives one to every shift-capable button
    // of every controller — a dozen targets stacked on the same two spots. Keep
    // only the one being edited, which is what a rider mapping their first
    // click actually sees.
    for (final pair in keymap.keyPairs) {
      if (pair.buttons.firstOrNull != shiftDown) pair.touchPosition = Offset.zero;
    }

    // The editor subtracts the difference between the display and the window
    // (a macOS notch) from every target's y. Under `flutter test` the display
    // is the host's, so without this the target renders well above the spot it
    // actually points at.
    tester.view.display.size = const Size(1200, 750) * 2.0;
    addTearDown(tester.view.display.resetSize);

    await asMacOS(
      () => captureWidget(
        tester,
        // A full-screen page, and one that measures itself against the screen:
        // it maps percentage positions onto the background, so MediaQuery has
        // to report the size the page is actually rendered at. Matching the
        // screenshot's 16:10 makes the mapped rect the whole surface.
        name: '09_mouse_editor',
        // Rendered large (at a lower pixel ratio) so a target near the right
        // edge still has room for its label — on a real screen it does.
        width: 1200,
        height: 750,
        pixelRatio: 2.0,
        padding: EdgeInsets.zero,
        // The editor never comes to rest (pumpAndSettle times out on it): the
        // drag targets and the Testbed overlay keep ticking.
        settle: false,
        builder: (context) => TouchAreaSetupPage(keyPair: pairFor(shiftDown)),
      ),
    );
  });

  testWidgets('Step 10 — the mapping table after both edits', (tester) async {
    pinApp();
    await asMacOS(
      () => captureWidget(
        tester,
        name: '10_mapping_custom',
        width: 420,
        builder: (context) => KeymapExplanation(keymap: keymap, filterDevice: click, onUpdate: () {}),
      ),
    );
  });

  testWidgets('Step 11 — everything the button editor offers on Android', (tester) async {
    pinApp();
    // Android drives the trainer app through the accessibility service, so its
    // handler supports touch and media but not keyboard — and it unlocks the
    // Android-only system actions. Swapping the handler (rather than calling
    // init) keeps the plugin streams AndroidActions.init subscribes to out of a
    // test that has no platform side.
    final BaseActions desktop = core.actionHandler;
    core.actionHandler = AndroidActions()..supportedApp = app;
    addTearDown(() => core.actionHandler = desktop);

    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      await captureWidget(
        tester,
        name: '11_button_edit_android',
        width: 320,
        // Cropped before "Other Actions": those rows are chosen by dart:io's
        // Platform, which no override can move off the macOS host, so they are
        // the desktop set and would be a lie in an Android shot.
        height: 645,
        builder: (context) => ButtonEditPage(
          keyPair: pairFor(shiftDown),
          device: click,
          keymap: keymap,
          trigger: ButtonTrigger.singleClick,
          onUpdate: () {},
        ),
      );
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
