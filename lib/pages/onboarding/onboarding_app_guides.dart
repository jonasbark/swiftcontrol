import 'package:bike_control/utils/i18n_extension.dart';
import 'package:bike_control/utils/keymap/apps/my_whoosh.dart';
import 'package:bike_control/utils/keymap/apps/rouvy.dart';
import 'package:bike_control/utils/keymap/apps/strappo.dart';
import 'package:bike_control/utils/keymap/apps/supported_app.dart';
import 'package:bike_control/utils/keymap/apps/training_peaks.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

/// The "Then in $app" mini-guide shown at the bottom of the onboarding
/// connection step: numbered steps plus optional screenshots and a link to
/// the full setup guide on the marketing site.
class OnboardingAppGuide {
  const OnboardingAppGuide({required this.steps, this.screenshotUrls = const [], this.guideUrl});

  final List<String> steps;
  final List<String> screenshotUrls;
  final String? guideUrl;
}

const String _shots = 'https://bikecontrol.app/images/';

OnboardingAppGuide onboardingGuideFor(BuildContext context, SupportedApp app) {
  final l = context.i18n;
  if (app is MyWhoosh) {
    return OnboardingAppGuide(
      steps: [l.onboardingGuideMyWhoosh1, l.onboardingGuideMyWhoosh2, l.onboardingGuideMyWhoosh3],
      screenshotUrls: [
        '$_shots' 'mywhoosh_obc/4-mywhoosh-connection-screen.jpg',
        '$_shots' 'mywhoosh_obc/5-mywhoosh-openbikecontrol.jpg',
        '$_shots' 'mywhoosh_obc/6-bikecontrol-connected.jpg',
      ],
      guideUrl: 'https://bikecontrol.app/blog/mywhoosh-bikecontrol-partnership/',
    );
  }
  if (app is Rouvy) {
    return OnboardingAppGuide(
      steps: [l.onboardingGuideRouvy1, l.onboardingGuideRouvy2],
      screenshotUrls: ['$_shots' 'blog_rouvy_screenshot.jpg'],
      guideUrl: 'https://bikecontrol.app/blog/rouvy-bikecontrol-integration/',
    );
  }
  if (app is TrainingPeaks) {
    return OnboardingAppGuide(
      steps: [l.onboardingGuideTp1, l.onboardingGuideTp2, l.onboardingGuideTp3],
      guideUrl: 'https://bikecontrol.app/blog/trainingpeaks-bikecontrol-partnership/',
    );
  }
  if (app is Strappo) {
    return OnboardingAppGuide(steps: [l.onboardingGuideStrappo1, l.onboardingGuideStrappo2]);
  }
  return OnboardingAppGuide(steps: [l.onboardingGuideGeneric1(app.name), l.onboardingGuideGeneric2]);
}
