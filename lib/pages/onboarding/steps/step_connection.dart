import 'package:bike_control/pages/onboarding/onboarding_app_guides.dart';
import 'package:bike_control/utils/i18n_extension.dart';
import 'package:bike_control/utils/keymap/apps/supported_app.dart';
import 'package:bike_control/utils/requirements/multi.dart';
import 'package:bike_control/widgets/apps/connection_tiles.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:url_launcher/url_launcher_string.dart';

Widget onboardingConnectionBody(
  BuildContext context, {
  required SupportedApp app,
  required Target target,
  required bool hasTrainer,
  required String? trainerName,
  required VoidCallback onUpdate,
}) {
  final tiles = buildConnectionMethodTiles(small: true, onUpdate: onUpdate);
  final guide = onboardingGuideFor(context, app);
  final scheme = Theme.of(context).colorScheme;

  return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text(context.i18n.onboardingConnectionTitle(app.name)).h4,
    Gap(6),
    Text(target == Target.thisDevice
            ? context.i18n.onboardingConnectionSubtitleLocal(app.name)
            : context.i18n.onboardingConnectionSubtitleNetwork(app.name))
        .small
        .muted,
    Gap(18),
    Text(context.i18n.recommendedConnectionMethods).xSmall.semiBold.muted,
    Gap(8),
    ...tiles.recommended,
    if (tiles.other.isNotEmpty) ...[
      Gap(8),
      Accordion(items: [
        AccordionItem(
          trigger: AccordionTrigger(child: Text(context.i18n.otherConnectionMethods).small),
          content: Column(children: tiles.other),
        ),
      ]),
    ],
    Gap(20),
    Text(context.i18n.onboardingThenInApp(app.name)).xSmall.semiBold.muted,
    Gap(8),
    Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration:
          BoxDecoration(border: Border.all(color: scheme.border, width: 1.5), borderRadius: BorderRadius.circular(12)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (var i = 0; i < guide.steps.length; i++)
          Padding(
            padding: EdgeInsets.only(top: i == 0 ? 0 : 10),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                width: 22,
                height: 22,
                alignment: Alignment.center,
                decoration: BoxDecoration(shape: BoxShape.circle, color: scheme.primary),
                child: DefaultTextStyle.merge(
                  style: const TextStyle(color: Color(0xFFFFFFFF)),
                  child: Text('${i + 1}').xSmall.semiBold,
                ),
              ),
              Gap(11),
              Expanded(child: Padding(padding: const EdgeInsets.only(top: 2), child: Text(guide.steps[i]).small)),
            ]),
          ),
        if (guide.screenshotUrls.isNotEmpty) ...[
          Gap(13),
          SizedBox(
            height: 118,
            child: ListView(scrollDirection: Axis.horizontal, children: [
              for (final url in guide.screenshotUrls)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.network(url, height: 118, errorBuilder: (_, _, _) => const SizedBox.shrink()),
                  ),
                ),
            ]),
          ),
        ],
        if (guide.guideUrl != null) ...[
          Gap(12),
          Button.ghost(
            onPressed: () => launchUrlString(guide.guideUrl!, mode: LaunchMode.externalApplication),
            child: Row(children: [
              Icon(LucideIcons.bookOpen, size: 15),
              Gap(8),
              Text(context.i18n.onboardingFullSetupGuide(app.name)).small,
              Gap(6),
              Icon(LucideIcons.externalLink, size: 13),
            ]),
          ),
        ],
      ]),
    ),
    if (hasTrainer) ...[
      Gap(20),
      Text(context.i18n.onboardingPairAsTrainer).xSmall.semiBold.muted,
      Gap(8),
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          border: Border.all(color: scheme.primary, width: 1.5),
          borderRadius: BorderRadius.circular(12),
          color: scheme.primary.withValues(alpha: 0.06),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(context.i18n.onboardingPairAsTrainerBody(app.name)).small,
          Gap(12),
          Container(
            padding: const EdgeInsets.all(11),
            decoration: BoxDecoration(
                color: scheme.card, border: Border.all(color: scheme.border), borderRadius: BorderRadius.circular(10)),
            child: Row(children: [
              Icon(LucideIcons.radio, size: 20, color: scheme.primary),
              Gap(12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${trainerName ?? ''} - BikeControl').small.semiBold,
                  Text(context.i18n.onboardingVirtualTrainerGears('${app.virtualGearAmount}')).xSmall.muted,
                ]),
              ),
            ]),
          ),
          Gap(12),
          Text(context.i18n.onboardingPairAsTrainerWarning(trainerName ?? '', app.name)).xSmall.muted,
        ]),
      ),
    ],
  ]);
}
