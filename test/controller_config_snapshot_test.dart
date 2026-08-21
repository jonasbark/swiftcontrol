@Tags(['screenshots'])
library;

import 'package:bike_control/bluetooth/devices/base_device.dart';
import 'package:bike_control/bluetooth/devices/thinkrider/thinkrider_vs200.dart';
import 'package:bike_control/bluetooth/devices/zwift/constants.dart';
import 'package:bike_control/bluetooth/devices/zwift/zwift_clickv2.dart';
import 'package:bike_control/main.dart' show screenshotMode;
import 'package:bike_control/pages/button_edit.dart';
import 'package:bike_control/pages/controller_settings.dart';
import 'package:bike_control/pages/home/chain_builder.dart';
import 'package:bike_control/pages/home/chain_inputs.dart';
import 'package:bike_control/pages/home/chain_state.dart';
import 'package:bike_control/utils/actions/base_actions.dart' show StubActions, SupportedMode;
import 'package:bike_control/utils/core.dart' show core;
import 'package:bike_control/utils/i18n_extension.dart';
import 'package:bike_control/utils/iap/iap_manager.dart';
import 'package:bike_control/utils/keymap/apps/my_whoosh.dart';
import 'package:bike_control/utils/keymap/buttons.dart';
import 'package:bike_control/utils/keymap/keymap.dart';
import 'package:bike_control/utils/requirements/multi.dart' show Target;
import 'package:bike_control/widgets/controller/controller_canvas.dart';
import 'package:bike_control/widgets/controller/trigger_assignment_popup.dart';
import 'package:bike_control/widgets/controller/trigger_conflict_dialog.dart';
import 'package:bike_control/widgets/home/chain_card.dart';
import 'package:bike_control/widgets/keymap_explanation.dart';
import 'package:bike_control/widgets/ui/animated_button_widget.dart';
import 'package:flutter/foundation.dart' show TargetPlatform, debugDefaultTargetPlatformOverride;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:universal_ble/universal_ble.dart';

import 'widget_snapshot.dart';

/// Snapshots the controller-configuration flow for the tutorial
/// "Configure Your Controller: Single Click, Double Click, Long Press":
/// the controller card on the main page (whose contour buttons are tappable),
/// the trigger popup that tap opens, the Controller Settings page it also leads
/// to, the mapping table's three trigger tiles, the button editor per trigger,
/// the Pro conflict dialog, the long-press repeat card, and the toggle-mode
/// fallback for controllers that can't report a held button.
///
/// Rendered as macOS, and deliberately as a NON-Pro user: the Pro badge on a
/// second trigger and the "Go Pro" button in the conflict dialog are half of
/// what the post is about, and both disappear for a subscriber.
///
/// Run: `flutter test --run-skipped test/controller_config_snapshot_test.dart`
Future<void> main() async {
  await ensureSnapshotHarness();

  // Real product names and real permission rows, not the anonymized marketing
  // variants the store boards use.
  screenshotMode = false;

  // The tutorial's actions are keyboard/click/media ones, so mirror what a
  // desktop handler reports.
  core.actionHandler = StubActions(
    supportedModes: const [SupportedMode.keyboard, SupportedMode.touch, SupportedMode.media],
  );

  // The harness leaves `isPurchased` on for the store boards. Everything below
  // is about what a free rider sees, so switch Pro back off explicitly.
  IAPManager.instance.isPurchased.value = false;
  IAPManager.instance.setProForTesting(enabled: false);

  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
    const MethodChannel('dev.leanflutter.plugins/keypress_simulator'),
    (call) async => true,
  );

  final app = MyWhoosh();
  // The Click V2, not the two-button V1: it is what most riders have now, and
  // ten buttons are what make "three gestures each" worth the trouble.
  final clickV2 = ZwiftClickV2(BleDevice(name: ZwiftClickV2.label, deviceId: '00:11:22:33:44:66'))
    ..firmwareVersion = '1.2.0'
    ..isConnected = true
    ..rssi = -51
    ..batteryLevel = 81;
  // A controller that cannot report a held button: its lever emits one edge and
  // nothing on release, so long press becomes a two-tap toggle instead.
  final vs200 = ThinkRiderVs200(BleDevice(name: 'ThinkRider VS200', deviceId: '00:11:22:33:44:77'))
    ..isConnected = true;

  core.connection.addDevices([clickV2, vs200]);
  core.settings.setTrainerApp(app);
  await core.settings.setLastTarget(Target.thisDevice);
  // The setup a MyWhoosh rider actually has: the native OpenBikeControl link
  // for shifting and menus, with Local switched on alongside it for keyboard
  // shortcuts. Without the native link every button MyWhoosh only exposes over
  // the protocol renders as "Not assigned", which is true but says nothing.
  await core.settings.setObpMdnsEnabled(true);
  core.settings.setLocalEnabled(true);

  // Devices first: init seeds the keymap from every connected controller's
  // buttons, which is what gives the mapping table its rows.
  core.actionHandler.init(app);

  final keymap = app.keymap;

  /// Registering a button a shipped keymap doesn't have copies that keymap into
  /// a profile of its own, and settings changes re-init the handler from prefs.
  /// Widgets take the keymap passed in, so pin the app before every capture to
  /// keep the two the same object.
  void pinApp() => core.actionHandler.supportedApp = app;

  const shiftUp = ZwiftButtons.shiftUpRight;

  KeyPair pairFor(ControllerButton button, ButtonTrigger trigger) =>
      keymap.getOrCreateKeyPair(button, trigger: trigger);

  /// Renders [body] with the framework's target platform pinned to macOS. Reset
  /// inside the body, not in a tearDown: the binding checks "no debug variable
  /// was changed" before tearDowns run.
  Future<void> asMacOS(Future<void> Function() body) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      await body();
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  }

  /// The main page's controller card body, mirroring `home_page.dart`'s private
  /// `_controllerBody`: the controller's real contour, with an
  /// [AnimatedButtonWidget] per button — the widget whose tap opens the trigger
  /// popup captured in step 2.
  Widget controllerBody(BuildContext context, BaseDevice device) {
    final size = 56 / Theme.of(context).scaling;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.muted,
        borderRadius: BorderRadius.circular(10),
      ),
      child: ControllerCanvas(
        layout: device.controllerLayout!,
        availableButtons: device.availableButtons,
        buttonSize: size,
        buttonBuilder: (button) => AnimatedButtonWidget(
          key: ValueKey(button.name),
          button: button,
          pressGeneration: 0,
          keymap: keymap,
          device: device,
          size: size,
          onUpdate: () {},
        ),
      ),
    );
  }

  testWidgets('Step 1 — the controller card on the main page', (tester) async {
    pinApp();
    // The genuine card: the home page's chain is derived from plain data, so
    // buildChain gives the same link the app shows for a connected, mapped
    // Click V2 running right-side-only (which is why no unlock step appears —
    // that mode has no unlock to do).
    final link = buildChain(
      const ChainInputs(
        bluetoothReady: true,
        controllers: [
          ControllerInput(
            name: ZwiftClickV2.label,
            deviceId: '00:11:22:33:44:66',
            presence: DevicePresence.connected,
            hasMappedButtons: true,
          ),
        ],
        app: AppInput(name: 'MyWhoosh'),
      ),
    ).firstWhere((l) => l.key == ChainLinkKey.controller);

    await asMacOS(
      () => captureWidget(
        tester,
        name: '01_controller_card',
        width: 420,
        builder: (context) => ChainCard(
          link: link,
          appName: 'MyWhoosh',
          tile: Icon(clickV2.icon, size: 22),
          title: link.title,
          statusLabel: context.i18n.connected,
          editLabel: context.i18n.chainEdit,
          onEdit: () {},
          body: controllerBody(context, clickV2),
        ),
      ),
    );
  });

  testWidgets('Step 2 — the trigger popup a tap on a button opens', (tester) async {
    pinApp();
    // Left exactly as the shipped MyWhoosh keymap has it: single click already
    // shifts, the other two triggers are free.
    await asMacOS(
      () => captureWidget(
        tester,
        name: '02_trigger_popup',
        width: 300,
        builder: (context) => buildTriggerAssignmentMenu(
          context: context,
          device: clickV2,
          button: shiftUp,
          keymap: keymap,
          onUpdate: () {},
        ),
      ),
    );
  });

  testWidgets('Step 3 — the Controller Settings page Edit opens', (tester) async {
    pinApp();
    await asMacOS(
      () => captureWidget(
        tester,
        name: '03_controller_settings',
        width: 900,
        // Cropped after the first few buttons — a Click V2 has ten, and the
        // page scrolls.
        height: 1136,
        padding: EdgeInsets.zero,
        // The page never comes to rest under `flutter test`: its device card
        // keeps a signal/battery poll ticking, so pumpAndSettle times out.
        settle: false,
        builder: (context) => ControllerSettingsPage(device: clickV2),
      ),
    );
  });

  testWidgets('Step 4 — the mapping table, one tile per trigger', (tester) async {
    pinApp();
    // Single click assigned, double click assigned too — which is what puts the
    // Pro badge on the second tile for a free rider.
    pairFor(shiftUp, ButtonTrigger.doubleClick)
      ..physicalKey = PhysicalKeyboardKey.keyH
      ..logicalKey = LogicalKeyboardKey.keyH;

    await asMacOS(
      () => captureWidget(
        tester,
        name: '04_mapping_triggers',
        // Above the 860 px the table uses to decide it is on a phone, so the
        // three triggers sit side by side — on a narrow window they stack.
        width: 900,
        builder: (context) => KeymapExplanation(keymap: keymap, filterDevice: clickV2, onUpdate: () {}),
      ),
    );
  });

  testWidgets('Step 5 — the Pro dialog a second trigger opens', (tester) async {
    pinApp();
    await asMacOS(
      () => captureWidget(
        tester,
        name: '05_trigger_conflict',
        width: 420,
        // The dialog paints its own barrier across the surface; padding on top
        // of that reads as a second, lighter frame.
        padding: EdgeInsets.zero,
        builder: (context) => buildTriggerConflictDialog(
          context: context,
          trigger: ButtonTrigger.doubleClick,
          onResolved: (_) {},
        ),
      ),
    );
  });

  testWidgets('Step 6 — the button editor for Double Click', (tester) async {
    pinApp();
    await asMacOS(
      () => captureWidget(
        tester,
        name: '06_button_edit_double_click',
        width: 320,
        // The top of the drawer: which gesture is being edited, and the start
        // of what it can be pointed at. Keyboard, click and media sit further
        // down, under Local / Remote Setting.
        height: 358,
        builder: (context) => ButtonEditPage(
          keyPair: pairFor(shiftUp, ButtonTrigger.doubleClick),
          device: clickV2,
          keymap: keymap,
          trigger: ButtonTrigger.doubleClick,
          onUpdate: () {},
        ),
      ),
    );
  });

  testWidgets('Step 7 — long press, with its repeat option', (tester) async {
    pinApp();
    // The repeat card only offers itself while long press has no action of its
    // own and single click has one.
    final longPress = pairFor(shiftUp, ButtonTrigger.longPress)
      ..physicalKey = null
      ..logicalKey = null
      ..modifiers = []
      ..touchPosition = Offset.zero
      ..inGameAction = null
      ..androidAction = null
      ..command = null;

    await asMacOS(
      () => captureWidget(
        tester,
        name: '07_button_edit_long_press',
        width: 320,
        // Just the header and the repeat card, which is what this shot is for.
        height: 180,
        builder: (context) => ButtonEditPage(
          keyPair: longPress,
          device: clickV2,
          keymap: keymap,
          trigger: ButtonTrigger.longPress,
          onUpdate: () {},
        ),
      ),
    );
  });

  testWidgets('Step 8 — toggle mode on a controller with no hold to report', (tester) async {
    pinApp();
    final button = vs200.availableButtons.first;
    final longPress = keymap.getOrCreateKeyPair(button, trigger: ButtonTrigger.longPress)
      ..physicalKey = PhysicalKeyboardKey.keyA
      ..logicalKey = LogicalKeyboardKey.keyA
      ..modifiers = []
      ..touchPosition = Offset.zero;

    await asMacOS(
      () => captureWidget(
        tester,
        name: '08_long_press_toggle',
        width: 320,
        // Just the header, the toggle-mode warning and the repeat card.
        height: 250,
        builder: (context) => ButtonEditPage(
          keyPair: longPress,
          device: vs200,
          keymap: keymap,
          trigger: ButtonTrigger.longPress,
          onUpdate: () {},
        ),
      ),
    );
  });

  testWidgets('Step 9 — the same controller in the mapping table', (tester) async {
    pinApp();
    await asMacOS(
      () => captureWidget(
        tester,
        name: '09_toggle_mode_table',
        width: 900,
        builder: (context) => KeymapExplanation(keymap: keymap, filterDevice: vs200, onUpdate: () {}),
      ),
    );
  });
}
