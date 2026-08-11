import 'package:bike_control/utils/i18n_extension.dart';
import 'package:bike_control/utils/keymap/apps/my_whoosh.dart';
import 'package:bike_control/utils/keymap/apps/rouvy.dart';
import 'package:bike_control/utils/keymap/apps/strappo.dart';
import 'package:bike_control/utils/keymap/apps/supported_app.dart';
import 'package:bike_control/utils/keymap/apps/training_peaks.dart';
import 'package:bike_control/pages/onboarding/widgets/onboarding_theme.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:url_launcher/url_launcher_string.dart';

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

/// The "Then in {app}" card: numbered steps, screenshots and a link to the full
/// guide on the marketing site.
///
/// Shared by the onboarding connection step and the home screen's trainer-app
/// instructions sheet. A rider who hits "not connected" after setup gets
/// exactly the same instructions — including the screenshots — that walked them
/// through it the first time, instead of a thinner second-hand retelling.
class OnboardingAppGuideCard extends StatelessWidget {
  const OnboardingAppGuideCard({super.key, required this.app, this.bordered = true});

  final SupportedApp app;

  /// The onboarding step draws its own border; a sheet doesn't need one.
  final bool bordered;

  @override
  Widget build(BuildContext context) {
    final guide = onboardingGuideFor(context, app);
    final scheme = Theme.of(context).colorScheme;
    final guideUrl = guide.guideUrl;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(bordered ? 14 : 0),
      decoration: bordered
          ? BoxDecoration(
              border: Border.all(color: scheme.border, width: 1.5),
              borderRadius: BorderRadius.circular(12),
            )
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < guide.steps.length; i++)
            Padding(
              padding: EdgeInsets.only(top: i == 0 ? 0 : 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 22,
                    height: 22,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(shape: BoxShape.circle, color: onboardingAccent(context)),
                    child: DefaultTextStyle.merge(
                      style: const TextStyle(color: Color(0xFFFFFFFF)),
                      child: Text('${i + 1}').xSmall.semiBold,
                    ),
                  ),
                  const Gap(11),
                  Expanded(
                    child: Padding(padding: const EdgeInsets.only(top: 2), child: Text(guide.steps[i]).small),
                  ),
                ],
              ),
            ),
          if (guide.screenshotUrls.isNotEmpty) ...[
            const Gap(13),
            SizedBox(
              height: 118,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (final url in guide.screenshotUrls)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.network(url, height: 118, errorBuilder: (_, _, _) => const SizedBox.shrink()),
                      ),
                    ),
                ],
              ),
            ),
          ],
          if (guideUrl != null) ...[
            const Gap(12),
            Button.ghost(
              onPressed: () => launchUrlString(guideUrl, mode: LaunchMode.externalApplication),
              child: Row(
                children: [
                  const Icon(LucideIcons.bookOpen, size: 15),
                  const Gap(8),
                  Flexible(child: Text(context.i18n.onboardingFullSetupGuide(app.name)).small),
                  const Gap(6),
                  const Icon(LucideIcons.externalLink, size: 13),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
