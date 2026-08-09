import 'package:bike_control/pages/onboarding/onboarding_models.dart';
import 'package:bike_control/pages/onboarding/onboarding_page.dart';
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
}
