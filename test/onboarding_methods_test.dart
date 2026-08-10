// The wizard's abstract Network/Bluetooth tiles must agree with the settings
// page's CoreLogic predicates for every registered app — TrainingPeaks
// (obpDirCon) and Rouvy (rouvyMdns) regressed exactly here.
import 'package:bike_control/pages/onboarding/onboarding_methods.dart';
import 'package:bike_control/utils/core.dart';
import 'package:bike_control/utils/keymap/apps/supported_app.dart';
import 'package:bike_control/utils/requirements/multi.dart';
import 'package:flutter_test/flutter_test.dart';

import 'widget_snapshot.dart';

Future<void> main() async {
  await ensureSnapshotHarness();

  testWidgets('network tile visibility matches CoreLogic for every app', (tester) async {
    for (final app in SupportedApp.supportedApps) {
      core.settings.setTrainerApp(app);
      final expected = core.logic.showObpMdnsEmulator || core.logic.showZwiftMsdnEmulator;
      expect(
        onboardingMethodVisible(OnboardingMethod.network, app),
        expected,
        reason: '${app.name}: network tile must match showObpMdnsEmulator/showZwiftMsdnEmulator',
      );
    }
  });

  testWidgets('local tile follows the target, like CoreLogic.showLocalControl', (tester) async {
    final app = SupportedApp.supportedApps.first;
    core.settings.setTrainerApp(app);
    await core.settings.setLastTarget(Target.otherDevice);
    expect(onboardingMethodVisible(OnboardingMethod.local, app), isFalse,
        reason: 'Local drives the app on THIS device — never offer it for another-device targets');
    await core.settings.setLastTarget(Target.thisDevice);
    expect(onboardingMethodVisible(OnboardingMethod.local, app), isTrue);
    expect(onboardingMethodVisible(OnboardingMethod.bluetooth, app), isFalse,
        reason: 'Bluetooth advertises to another device — pointless on the same one');
  });

  testWidgets('bluetooth tile visibility matches app support on other-device target', (tester) async {
    await core.settings.setLastTarget(Target.otherDevice);
    for (final app in SupportedApp.supportedApps) {
      core.settings.setTrainerApp(app);
      final expected = app.supports(AppConnectionMethod.obpBle) || app.supports(AppConnectionMethod.zwiftBle);
      expect(
        onboardingMethodVisible(OnboardingMethod.bluetooth, app),
        expected,
        reason: '${app.name}: bluetooth tile must match obpBle/zwiftBle support',
      );
    }
  });
}
