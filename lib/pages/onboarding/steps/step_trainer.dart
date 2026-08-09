import 'package:bike_control/bluetooth/devices/proxy/proxy_device.dart';
import 'package:bike_control/utils/i18n_extension.dart';
import 'package:bike_control/utils/keymap/apps/supported_app.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:url_launcher/url_launcher_string.dart';

bool onboardingTrainerBridged(List<ProxyDevice> trainers) =>
    trainers.any((t) => t.isStartedListenable.value || t.isConnectedListenable.value);

Widget onboardingTrainerBody(BuildContext context,
    {required SupportedApp app, required List<ProxyDevice> trainers, required void Function(ProxyDevice) onPick}) {
  final bridged = trainers.where((t) => t.isStartedListenable.value || t.isConnectedListenable.value).toList();
  final scheme = Theme.of(context).colorScheme;

  if (bridged.isNotEmpty) {
    final t = bridged.first;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(context.i18n.onboardingTrainerConnectedTitle).h4,
      Gap(6),
      Text(context.i18n.onboardingTrainerConnectedSubtitle).small.muted,
      Gap(18),
      Container(
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          border: Border.all(color: const Color(0xFF22C55E), width: 1.5),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(children: [
          Icon(LucideIcons.bike, size: 20, color: const Color(0xFF22C55E)),
          Gap(12),
          Expanded(child: Text(t.name).small.semiBold),
          SecondaryBadge(child: Text(context.i18n.onboardingDeviceConnected)),
        ]),
      ),
      Gap(12),
      Text(context.i18n.onboardingTrainerNextStepNote(app.name)).xSmall.muted,
    ]);
  }

  Widget benefit(IconData icon, String title, String sub) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
        decoration: BoxDecoration(color: scheme.muted, borderRadius: BorderRadius.circular(10)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 18, color: scheme.primary),
          Gap(12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title).small.semiBold,
              Text(sub).xSmall.muted,
            ]),
          ),
        ]),
      );

  return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text(context.i18n.onboardingTrainerTitle).h4,
    Gap(6),
    Text(context.i18n.onboardingTrainerSubtitle).small.muted,
    Gap(16),
    benefit(LucideIcons.slidersHorizontal, context.i18n.onboardingTrainerBenefitRatiosTitle,
        context.i18n.onboardingTrainerBenefitRatiosSub),
    benefit(LucideIcons.gauge, context.i18n.onboardingTrainerBenefitResistanceTitle,
        context.i18n.onboardingTrainerBenefitResistanceSub),
    benefit(LucideIcons.blocks, context.i18n.onboardingTrainerBenefitAppsTitle,
        context.i18n.onboardingTrainerBenefitAppsSub),
    Gap(14),
    Row(children: [
      Text(context.i18n.onboardingNearbyTrainers).xSmall.semiBold.muted,
      Gap(8),
      SizedBox(width: 12, height: 12, child: CircularProgressIndicator()),
    ]),
    Gap(8),
    if (trainers.isEmpty) Text(context.i18n.lookingForSmartTrainers).xSmall.muted,
    for (final t in trainers)
      Container(
        margin: const EdgeInsets.only(bottom: 8),
        child: Button.card(
          onPressed: () => onPick(t),
          child: Row(children: [
            Icon(LucideIcons.bike, size: 20),
            Gap(12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(t.name).small.semiBold,
                Text(context.i18n.onboardingTrainerMeta).xSmall.muted,
              ]),
            ),
            Icon(LucideIcons.chevronRight, size: 16),
          ]),
        ),
      ),
    Gap(10),
    Button.ghost(
      onPressed: () => launchUrlString('https://bikecontrol.app/virtual-shifting', mode: LaunchMode.externalApplication),
      child: Row(children: [
        Icon(LucideIcons.bookOpen, size: 15),
        Gap(8),
        Text(context.i18n.onboardingTrainerHowItWorks).small,
        Gap(6),
        Icon(LucideIcons.externalLink, size: 13),
      ]),
    ),
  ]);
}
