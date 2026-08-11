import 'package:bike_control/bluetooth/devices/zwift/constants.dart';
import 'package:bike_control/bluetooth/devices/zwift/zwift_clickv2_left_side.dart';
import 'package:bike_control/bluetooth/devices/zwift/zwift_ride.dart';
import 'package:bike_control/main.dart';
import 'package:bike_control/utils/click_v2_onboarding.dart';
import 'package:bike_control/utils/core.dart';
import 'package:bike_control/utils/i18n_extension.dart';
import 'package:bike_control/utils/keymap/apps/custom_app.dart';
import 'package:bike_control/utils/keymap/buttons.dart';
import 'package:bike_control/utils/keymap/keymap.dart';
import 'package:bike_control/utils/keymap/manager.dart';
import 'package:bike_control/widgets/controller/controller_layout.dart';
import 'package:bike_control/widgets/new_unlock_method_toggle.dart';
import 'package:bike_control/widgets/ui/toast.dart';
import 'package:flutter/foundation.dart';
import 'package:prop/prop.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

class ZwiftClickV2RightSide extends ZwiftRide {
  ZwiftClickV2RightSide(super.scanResult)
    : super(
        isBeta: false,
        availableButtons: [
          ZwiftButtons.a,
          ZwiftButtons.b,
          ZwiftButtons.y,
          ZwiftButtons.z,
          ZwiftButtons.shiftUpRight,
        ],
      );

  @override
  String get latestFirmwareVersion => '1.2.0';

  @override
  bool get canVibrate => false;

  /// Held out of the connect queue until the rider has chosen an unlock mode.
  /// Zwift Click V2 behaviour depends entirely on that choice, so connecting
  /// first would hand them a controller that half-works for reasons they have
  /// not been told about yet.
  ///
  /// After the choice, left-side-only mode deliberately leaves the right
  /// controller unused ("only the left controller sends button presses") —
  /// connecting it anyway would just burn its battery and disturb
  /// ClickLogic's restart cycle. This also keeps ClickV2Onboarding's
  /// _connectPending from picking it up: connectDevice still runs, but
  /// [connect] below is a no-op while this is false.
  @override
  bool get shouldAutoConnect => !ClickV2Onboarding.isPending && core.settings.getUnlockWithZwift();

  @override
  Future<void> connect() async {
    // Mirrors ProxyDevice: stay listed and keep the queue's listener wiring,
    // but open no transport and run no handshake while onboarding is pending.
    if (!shouldAutoConnect) return;
    await super.connect();
  }

  @override
  List<int> get startCommand => ZwiftConstants.RIDE_ON + ZwiftConstants.RESPONSE_START_CLICK_V2;

  @override
  ControllerLayout get controllerLayout => ControllerLayout(
    aspectRatio: 215 / 252.9,
    shape: ContourShape.pill,
    svgAsset: 'assets/contours/zwift_click_v2_right_side.svg',
    positions: {
      // Right puck — face-button diamond. Per the physical device: Y top,
      // Z left, A right, B bottom. Plus (shift-up-right) sits under B.
      ZwiftButtons.y: const Offset(0.500, 0.25),
      ZwiftButtons.z: const Offset(0.252, 0.44),
      ZwiftButtons.a: const Offset(0.723, 0.44),
      ZwiftButtons.b: const Offset(0.500, 0.62),
      ZwiftButtons.shiftUpRight: const Offset(0.500, 0.87),
    },
  );

  @override
  String toString() {
    return "Zwift Click V2 (right)";
  }

  /// See [ZwiftClickV2LeftSide.displayName]. This side doesn't extend
  /// [ZwiftClickV2], so the unsuffixed name is spelled out rather than taken
  /// from `super.toString()` (which would yield the advertised BLE name).
  @override
  String displayName(BuildContext context) =>
      context.i18n.deviceSideRight(screenshotMode ? 'Controller' : 'Zwift Click V2');

  @override
  Future<void> setupHandshake() async {
    await sendCommandBuffer(Uint8List.fromList(startCommand));
    ClickLogic.setupHandshake(services!, device.deviceId, isRight: true);
  }

  @override
  List<Widget> showAdditionalInformation(BuildContext context) {
    final hasLeftSide = core.connection.devices.whereType<ZwiftClickV2LeftSide>().isNotEmpty;
    if (!hasLeftSide) return [];
    return [
      Text(context.i18n.unlock_useRightSideOnlyDescription).xSmall.normal,
      SizedBox(
        width: double.infinity,
        child: Button.outline(
          onPressed: () => _useRightSideOnly(context),
          child: Text(context.i18n.unlock_useRightSideOnly),
        ),
      ),
    ];
  }

  /// Detail page only: the new-unlock-method toggle lives under "Preferences"
  /// so it doesn't show on the compact overview card.
  @override
  Widget? buildPreferences(BuildContext context) {
    final superPreferences = super.buildPreferences(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 12,
      children: [
        if (superPreferences != null) superPreferences,
        const NewUnlockMethodToggle(),
      ],
    );
  }

  /// Switches to a "right side only" setup: the left controller (which needs
  /// unlocking / restarts) is dropped and the right side covers gear shifting
  /// on its own — ＋ still shifts up, B takes over shifting down.
  Future<void> _useRightSideOnly(BuildContext context) async {
    // Read localised text before the awaits below remove this card.
    final confirmation = context.i18n.unlock_rightSideOnlyConfigured;

    // Remap the keymap while both sides are still connected: if this has to fork
    // a built-in profile into a custom copy, the copy should keep every
    // connected controller's existing mappings (the left side's included).
    configureRightSideShiftingKeymap();

    // Then ignore (don't just disconnect) the left side, otherwise the active
    // scan reconnects it within seconds. Ignoring is persistent and reversible
    // from the Ignored Devices list.
    final leftSides = core.connection.devices.whereType<ZwiftClickV2LeftSide>().toList();
    for (final left in leftSides) {
      await core.connection.disconnect(left, forget: true, persistForget: true);
    }

    buildToast(title: confirmation);
  }

  /// Remaps the active trainer-app keymap so the right side alone can shift in
  /// both directions: ＋ (shiftUpRight) shifts up, B shifts down. B loses its
  /// default "back"/Escape binding so it becomes a dedicated down-shift.
  ///
  /// Built-in app keymaps are code-defined templates that reset to their
  /// defaults on restart, and [Settings.setKeyMap] only persists key pairs for
  /// custom profiles. So, mirroring the button editor, a built-in profile is
  /// first forked into a custom copy (`"App (Copy)"`) which the remap then edits
  /// and persists — otherwise the change would be lost on the next launch.
  @visibleForTesting
  void configureRightSideShiftingKeymap() {
    final app = core.actionHandler.supportedApp;
    if (app == null) return;

    if (app is! CustomApp) {
      KeymapManager().duplicateSync(app.name, '${app.name} (Copy)');
    }

    final keymap = core.actionHandler.supportedApp?.keymap;
    if (keymap == null) return;

    keymap.getOrCreateKeyPair(ZwiftButtons.shiftUpRight, trigger: ButtonTrigger.singleClick).inGameAction =
        InGameAction.shiftUp;

    final shiftDown = keymap.getOrCreateKeyPair(ZwiftButtons.b, trigger: ButtonTrigger.singleClick);
    shiftDown.inGameAction = InGameAction.shiftDown;
    shiftDown.physicalKey = null;
    shiftDown.logicalKey = null;
    shiftDown.modifiers = [];

    keymap.signalUpdate();

    final activeApp = core.actionHandler.supportedApp;
    if (activeApp != null) {
      core.settings.setKeyMap(activeApp);
    }
  }
}
