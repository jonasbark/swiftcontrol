import 'package:bike_control/bluetooth/devices/proxy/proxy_device.dart';
import 'package:bike_control/bluetooth/devices/sram/sram_axs.dart';
import 'package:bike_control/pages/onboarding/onboarding_models.dart';
import 'package:bike_control/pages/onboarding/onboarding_page.dart';
import 'package:bike_control/pages/onboarding/onboarding_sheets.dart';
import 'package:bike_control/pages/onboarding/steps/step_app.dart';
import 'package:bike_control/pages/onboarding/steps/step_connection.dart';
import 'package:bike_control/pages/onboarding/steps/step_controller.dart';
import 'package:bike_control/pages/onboarding/steps/step_done.dart';
import 'package:bike_control/pages/onboarding/steps/step_trainer.dart';
import 'package:bike_control/pages/onboarding/steps/step_where.dart';
import 'package:bike_control/pages/onboarding/widgets/onboarding_button_hint.dart';
import 'package:bike_control/utils/keymap/apps/my_whoosh.dart';
import 'package:bike_control/utils/keymap/apps/supported_app.dart';
import 'package:bike_control/utils/requirements/multi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:universal_ble/universal_ble.dart';

import 'widget_snapshot.dart';

Future<void> main() async {
  await ensureSnapshotHarness();

  Widget shell(BuildContext context, {required OnboardingStep step}) => SizedBox(
        height: 720,
        child: onboardingShell(
          context,
          step: step,
          body: const Text('body placeholder'),
          footerActions: [PrimaryButton(onPressed: () {}, child: const Text('Continue'))],
          onBack: step == OnboardingStep.app ? null : () {},
          onHelp: () {},
          onSelectStep: (_) {},
        ),
      );

  testWidgets('shell mobile', (tester) async {
    await captureWidget(tester, name: 'onboarding_shell_mobile', width: 380,
        builder: (c) => shell(c, step: OnboardingStep.controller));
  });

  testWidgets('shell desktop', (tester) async {
    await captureWidget(tester, name: 'onboarding_shell_desktop', width: 1000,
        builder: (c) => shell(c, step: OnboardingStep.controller));
  });

  // Wrap a sheet body so it reads like the bottom sheet (surface + padding).
  Widget sheet(Widget body) => Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: body,
        ),
      );

  testWidgets('help sheet', (tester) async {
    await captureWidget(tester, name: 'onboarding_help_sheet', width: 380,
        builder: (c) => sheet(onboardingHelpSheetBody(c, step: OnboardingStep.controller, onClose: () {})));
  });

  testWidgets('permission denied sheet', (tester) async {
    await captureWidget(tester, name: 'onboarding_permission_denied_sheet', width: 380,
        builder: (c) => sheet(permissionDeniedSheetBody(c, onContinueAnyway: () {}, onAllow: () {})));
  });

  testWidgets('step app unselected', (tester) async {
    await captureWidget(tester, name: 'onboarding_step_app', width: 380,
        builder: (c) => onboardingAppBody(c, selected: null, onSelect: (_) {}));
  });

  testWidgets('step app selected', (tester) async {
    await captureWidget(tester, name: 'onboarding_step_app_selected', width: 380,
        builder: (c) => onboardingAppBody(
              c,
              selected: SupportedApp.supportedApps.first,
              onSelect: (_) {},
            ));
  });

  testWidgets('step app wide', (tester) async {
    await captureWidget(tester, name: 'onboarding_step_app_wide', width: 640,
        builder: (c) => onboardingAppBody(c, selected: null, onSelect: (_) {}));
  });

  testWidgets('step where unselected', (tester) async {
    await captureWidget(tester, name: 'onboarding_step_where', width: 380,
        builder: (c) => onboardingWhereBody(
              c,
              app: SupportedApp.supportedApps.first,
              selected: null,
              onSelect: (_) {},
            ));
  });

  testWidgets('step where selected', (tester) async {
    await captureWidget(tester, name: 'onboarding_step_where_selected', width: 380,
        builder: (c) => onboardingWhereBody(
              c,
              app: SupportedApp.supportedApps.first,
              selected: Target.otherDevice,
              onSelect: (_) {},
            ));
  });

  // ── Step controller: permission / scanning / empty / list phases ──────────
  final connectedDevice = SramAxs(BleDevice(deviceId: 'snap', name: 'SRAM Rival AXS'))..isConnected = true;
  final connectingDevice = SramAxs(BleDevice(deviceId: 'snap-2', name: 'SRAM Force AXS'));

  testWidgets('step controller permission', (tester) async {
    await captureWidget(tester, name: 'onboarding_step_controller_permission', width: 380,
        builder: (c) => onboardingControllerBody(c, phase: ControllerPhase.permission, devices: const [], appName: 'Zwift'));
  });

  // The wifi scan animation loops forever — settle:false, like the SRAM
  // "running"/"authorize" stages in sram_states_snapshot_test.dart.
  testWidgets('step controller scanning', (tester) async {
    await captureWidget(tester, name: 'onboarding_step_controller_scanning', width: 380, settle: false,
        builder: (c) => onboardingControllerBody(c, phase: ControllerPhase.scanning, devices: const [], appName: 'Zwift'));
  });

  testWidgets('step controller empty', (tester) async {
    await captureWidget(tester, name: 'onboarding_step_controller_empty', width: 380,
        builder: (c) => onboardingControllerBody(c, phase: ControllerPhase.empty, devices: const [], appName: 'Zwift'));
  });

  // The "still scanning" spinner in the list phase is also infinite.
  testWidgets('step controller list', (tester) async {
    await captureWidget(tester, name: 'onboarding_step_controller_list', width: 380, settle: false,
        builder: (c) => onboardingControllerBody(
              c,
              phase: ControllerPhase.list,
              devices: [connectedDevice, connectingDevice],
              appName: 'Zwift',
            ));
  });

  // The pulsing dot animation loops forever — settle:false, like the other
  // infinite-animation captures above.
  testWidgets('button hint', (tester) async {
    await captureWidget(tester, name: 'onboarding_button_hint', width: 380, settle: false,
        builder: (c) => OnboardingButtonHint(onContinue: () {}));
  });

  // ── Step 4: virtual shifting ────────────────────────────────────────────
  // The "nearby trainers" spinner is also infinite — settle:false, like the
  // other loading-state captures above.
  testWidgets('step trainer intro', (tester) async {
    await captureWidget(tester, name: 'onboarding_step_trainer', width: 380, settle: false,
        builder: (c) => onboardingTrainerBody(
              c,
              app: SupportedApp.supportedApps.first,
              trainers: const <ProxyDevice>[],
              onPick: (_) {},
            ));
  });

  // ── Step 5: connection methods + "Then in $app" guide + bridge card ────
  // Network screenshots fail to load in tests — the errorBuilder swallows
  // that and vanishes the image, which is the offline behaviour working as
  // intended, so settle:false avoids pumpAndSettle hanging on the retries.
  testWidgets('step connection no trainer', (tester) async {
    await captureWidget(tester, name: 'onboarding_step_connection', width: 380, settle: false,
        builder: (c) => onboardingConnectionBody(
              c,
              app: MyWhoosh(),
              target: Target.otherDevice,
              hasTrainer: false,
              trainerName: null,
              onUpdate: () {},
            ));
  });

  testWidgets('step connection with trainer', (tester) async {
    await captureWidget(tester, name: 'onboarding_step_connection_trainer', width: 380, settle: false,
        builder: (c) => onboardingConnectionBody(
              c,
              app: MyWhoosh(),
              target: Target.otherDevice,
              hasTrainer: true,
              trainerName: 'KICKR CORE',
              onUpdate: () {},
            ));
  });

  // ── Step 6: done / test mode / completion ──────────────────────────────
  testWidgets('step done no trainer', (tester) async {
    await captureWidget(tester, name: 'onboarding_step_done', width: 380,
        builder: (c) => onboardingDoneBody(
              c,
              app: MyWhoosh(),
              controllerName: 'SRAM Rival AXS',
              trainerName: null,
              appConnected: true,
              trainerAppConnected: false,
              reduceMotion: true,
              showTestMode: true,
            ));
  });

  testWidgets('step done with trainer', (tester) async {
    await captureWidget(tester, name: 'onboarding_step_done_trainer', width: 380,
        builder: (c) => onboardingDoneBody(
              c,
              app: MyWhoosh(),
              controllerName: 'SRAM Rival AXS',
              trainerName: 'KICKR CORE',
              appConnected: true,
              trainerAppConnected: false,
              reduceMotion: true,
              showTestMode: true,
            ));
  });

  // Purchased users re-running the guide shouldn't see the "test mode" card.
  testWidgets('step done purchased (no test mode card)', (tester) async {
    await captureWidget(tester, name: 'onboarding_step_done_purchased', width: 380,
        builder: (c) => onboardingDoneBody(
              c,
              app: MyWhoosh(),
              controllerName: 'SRAM Rival AXS',
              trainerName: null,
              appConnected: true,
              trainerAppConnected: false,
              reduceMotion: true,
              showTestMode: false,
            ));
  });
}
