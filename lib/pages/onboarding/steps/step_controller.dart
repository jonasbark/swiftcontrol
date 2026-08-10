import 'package:bike_control/bluetooth/devices/base_device.dart';
import 'package:bike_control/bluetooth/devices/sram/sram_axs.dart';
import 'package:bike_control/bluetooth/devices/zwift/zwift_clickv2.dart';
import 'package:bike_control/bluetooth/devices/zwift/zwift_clickv2_right_side.dart';
import 'package:bike_control/pages/onboarding/onboarding_models.dart';
import 'package:bike_control/utils/click_v2_onboarding.dart';
import 'package:bike_control/utils/i18n_extension.dart';
import 'package:bike_control/utils/keymap/buttons.dart';
import 'package:bike_control/utils/core.dart';
import 'package:bike_control/widgets/controller/controller_canvas.dart';
import 'package:bike_control/widgets/ui/animated_button_widget.dart';
import 'package:bike_control/widgets/guided_operation_sheet.dart';
import 'package:bike_control/widgets/ui/wifi_animation.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

Widget _infoRow(BuildContext context, IconData icon, String title, String sub) {
  return Container(
    margin: const EdgeInsets.only(bottom: 8),
    padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.muted,
      borderRadius: BorderRadius.circular(10),
    ),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(icon, size: 18),
      Gap(12),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title).small.semiBold,
          if (sub.isNotEmpty) Text(sub).xSmall.muted,
        ]),
      ),
    ]),
  );
}

/// Whether a connected controller [device] still needs its guided sub-flow
/// run (SRAM AXS "disable on-device shifting" setup, or Click V2 unlock).
bool onboardingDeviceNeedsSetup(BaseDevice device) {
  // A new Click V2 is held out of the connect queue until the rider has
  // picked an unlock mode in the existing ClickV2OnboardingPage explainer.
  if (device is ZwiftClickV2 || device is ZwiftClickV2RightSide) return ClickV2Onboarding.isPending;
  if (device is SramAxs) return device.needsGuidedSetup;
  return false;
}

Widget onboardingDeviceRow(BuildContext context, BaseDevice device, {bool needsSetup = false}) {
  final connected = device.isConnected;
  final scheme = Theme.of(context).colorScheme;
  return Container(
    margin: const EdgeInsets.only(bottom: 8),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      border: Border.all(color: connected ? const Color(0xFF22C55E) : scheme.border, width: 1.5),
      borderRadius: BorderRadius.circular(12),
      color: scheme.card,
    ),
    child: Row(children: [
      Icon(connected ? LucideIcons.check : device.icon, size: 20, color: connected ? const Color(0xFF22C55E) : null),
      Gap(12),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(device.name).small.semiBold,
          // A device held for setup (Click V2 pending its unlock-mode choice)
          // is deliberately not connecting — don't pretend it is.
          Text(connected
                  ? context.i18n.onboardingDeviceConnected
                  : needsSetup
                      ? context.i18n.onboardingSetupNeeded
                      : context.i18n.onboardingDeviceConnecting)
              .xSmall
              .muted,
        ]),
      ),
      if (needsSetup)
        SecondaryBadge(child: Text(context.i18n.onboardingSetupNeeded))
      else if (connected)
        SecondaryBadge(child: Text(context.i18n.onboardingDeviceConnected)),
    ]),
  );
}

Widget onboardingControllerBody(BuildContext context,
    {required ControllerPhase phase,
    required List<BaseDevice> devices,
    required String appName,
    Map<String, ControllerButton> pressedButtons = const {},
    Map<String, int> pressGenerations = const {},
    VoidCallback? onUpdate}) {
  final reduceMotion = MediaQuery.of(context).disableAnimations;
  final scheme = Theme.of(context).colorScheme;
  final anyConnected = devices.any((d) => d.isConnected);

  switch (phase) {
    case ControllerPhase.permission:
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(context.i18n.onboardingBluetoothTitle).h4,
        Gap(6),
        Text(context.i18n.onboardingBluetoothSubtitle).small.muted,
        Gap(16),
        Center(
          child: StageBadge(
            icon: LucideIcons.bluetooth,
            tone: scheme.primary,
            wash: scheme.primary.withValues(alpha: 0.1),
            reduceMotion: reduceMotion,
          ),
        ),
        Gap(20),
        _infoRow(context, LucideIcons.radar, context.i18n.onboardingBluetoothFindTitle, context.i18n.onboardingBluetoothFindSub),
        _infoRow(
            context, LucideIcons.bell, context.i18n.onboardingBluetoothNotifyTitle, context.i18n.onboardingBluetoothNotifySub),
        Gap(6),
        _infoRow(context, LucideIcons.shieldCheck, context.i18n.onboardingBluetoothPrivacy, ''),
      ]);
    case ControllerPhase.scanning:
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(context.i18n.onboardingScanTitle).h4,
        Gap(6),
        Text(context.i18n.onboardingScanSubtitle).small.muted,
        Gap(24),
        Center(child: SmoothWifiAnimation()),
        Gap(20),
        Center(child: Text(context.i18n.scanningForDevices).small.muted),
      ]);
    case ControllerPhase.empty:
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(context.i18n.onboardingScanEmptyTitle).h4,
        Gap(6),
        Text(context.i18n.onboardingScanEmptySubtitle).small.muted,
        Gap(18),
        _infoRow(
            context, LucideIcons.power, context.i18n.onboardingScanEmptyWakeTitle, context.i18n.onboardingScanEmptyWakeSub),
        _infoRow(context, LucideIcons.unlink, context.i18n.onboardingScanEmptyDisconnectTitle,
            context.i18n.onboardingScanEmptyDisconnectSub),
        _infoRow(context, LucideIcons.ruler, context.i18n.onboardingScanEmptyCloserTitle,
            context.i18n.onboardingScanEmptyCloserSub),
      ]);
    case ControllerPhase.list:
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(anyConnected ? context.i18n.onboardingControllerReadyTitle : context.i18n.onboardingControllerListTitle).h4,
        Gap(6),
        Text(anyConnected ? context.i18n.onboardingControllerReadySubtitle : context.i18n.onboardingControllerListSubtitle)
            .small
            .muted,
        Gap(16),
        for (final d in devices) onboardingDeviceRow(context, d, needsSetup: onboardingDeviceNeedsSetup(d)),
        // Contour of the first connected controller so riders can see the
        // buttons they just gained (same canvas the home screen uses).
        if (devices.where((d) => d.isConnected && d.controllerLayout != null).firstOrNull case final hero?) ...[
          Gap(6),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              border: Border.all(color: scheme.border, width: 1.5),
              borderRadius: BorderRadius.circular(12),
              color: scheme.card,
            ),
            child: Builder(builder: (context) {
              // Same rendering as the home screen's device card: keymap-aware
              // buttons that flash when the rider presses them on the hardware.
              final pressed = pressedButtons[hero.uniqueId];
              final generation = pressGenerations[hero.uniqueId] ?? 0;
              final keymap = core.actionHandler.supportedApp?.keymap;
              final size = 56 / Theme.of(context).scaling;
              return ControllerCanvas(
                layout: hero.controllerLayout!,
                availableButtons: hero.availableButtons,
                buttonSize: size,
                buttonBuilder: (btn) => AnimatedButtonWidget(
                  key: ValueKey(btn.name),
                  button: btn,
                  pressGeneration: pressed?.name == btn.name ? generation : 0,
                  keymap: keymap,
                  device: hero,
                  size: size,
                  onUpdate: onUpdate ?? () {},
                ),
              );
            }),
          ),
        ],
        // Once a controller is connected the job is done — don't keep
        // suggesting the wizard is waiting for something.
        if (!anyConnected) ...[
          Gap(10),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            SizedBox(width: 14, height: 14, child: CircularProgressIndicator(size: 14)),
            Gap(8),
            Text(context.i18n.onboardingStillScanning).xSmall.muted,
          ]),
        ],
        if (anyConnected) ...[
          Gap(12),
          _infoRow(context, LucideIcons.lightbulb, context.i18n.onboardingControllerMapped(appName), ''),
        ],
      ]);
  }
}
