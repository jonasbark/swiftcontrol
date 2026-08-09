import 'package:bike_control/pages/onboarding/onboarding_models.dart';
import 'package:bike_control/pages/onboarding/onboarding_page.dart';
import 'package:bike_control/pages/onboarding/onboarding_sheets.dart';
import 'package:bike_control/pages/onboarding/steps/step_app.dart';
import 'package:bike_control/pages/onboarding/steps/step_where.dart';
import 'package:bike_control/utils/keymap/apps/supported_app.dart';
import 'package:bike_control/utils/requirements/multi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

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
}
