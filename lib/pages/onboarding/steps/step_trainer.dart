import 'package:bike_control/pages/onboarding/widgets/onboarding_theme.dart';
import 'package:bike_control/bluetooth/devices/proxy/proxy_device.dart';
import 'package:bike_control/utils/i18n_extension.dart';
import 'package:bike_control/utils/keymap/apps/supported_app.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:url_launcher/url_launcher_string.dart';

bool onboardingTrainerBridged(List<ProxyDevice> trainers) => trainers.any((t) => t.isBridged);

Widget _alternative(BuildContext context, IconData icon, String title, String body) {
  final scheme = Theme.of(context).colorScheme;
  return Container(
    margin: const EdgeInsets.only(bottom: 8),
    padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
    decoration: BoxDecoration(color: scheme.muted, borderRadius: BorderRadius.circular(10)),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(icon, size: 18, color: onboardingAccent(context)),
      Gap(12),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title).small.semiBold,
          Text(body).xSmall.muted,
        ]),
      ),
    ]),
  );
}

Widget onboardingTrainerBody(BuildContext context,
    {required SupportedApp app,
    required List<ProxyDevice> trainers,
    required void Function(ProxyDevice) onPick,
    bool virtualShiftingBlocked = false}) {
  final bridged = trainers.where((t) => t.isBridged).toList();
  final scheme = Theme.of(context).colorScheme;

  // MyWhoosh on Android can't see a network virtual bike, so a bridge on this
  // same device would never be found — explain it and name the two setups
  // that do work instead of silently hiding the step.
  if (bridged.isEmpty && virtualShiftingBlocked) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(context.i18n.onboardingVsBlockedTitle).h4,
      Gap(6),
      Text(context.i18n.onboardingVsBlockedSubtitle(app.name)).small.muted,
      Gap(16),
      Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          color: const Color(0x1AF59E0B),
          border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.5)),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(LucideIcons.triangleAlert, size: 16, color: const Color(0xFFF59E0B)),
          Gap(10),
          Expanded(child: Text(context.i18n.onboardingVsBlockedExplainer(app.name)).xSmall),
        ]),
      ),
      Gap(16),
      Text(context.i18n.onboardingVsBlockedAlternatives).xSmall.semiBold.muted,
      Gap(8),
      _alternative(context, LucideIcons.monitorSmartphone, context.i18n.onboardingVsBlockedAltAppTitle(app.name),
          context.i18n.onboardingVsBlockedAltAppBody(app.name)),
      _alternative(context, LucideIcons.bluetooth, context.i18n.onboardingVsBlockedAltBtTitle,
          context.i18n.onboardingVsBlockedAltBtBody(app.name)),
      Gap(6),
      Button.ghost(
        style: ButtonStyle.ghost().withPadding(padding: EdgeInsets.zero),
        onPressed: () => launchUrlString(
            'https://bikecontrol.app/blog/virtual-shifting-with-and-without-bikecontrol/',
            mode: LaunchMode.externalApplication),
        child: Row(children: [
          Icon(LucideIcons.bookOpen, size: 15),
          Gap(8),
          Flexible(child: Text(context.i18n.onboardingTrainerHowItWorks).small),
          Gap(6),
          Icon(LucideIcons.externalLink, size: 13),
        ]),
      ),
    ]);
  }

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
          Icon(icon, size: 18, color: onboardingAccent(context)),
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
          onPressed: t.isStarting.value ? null : () => onPick(t),
          child: Row(children: [
            Icon(LucideIcons.bike, size: 20),
            Gap(12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(t.name).small.semiBold,
                Text(t.isStarting.value
                        ? context.i18n.onboardingDeviceConnecting
                        : context.i18n.onboardingTrainerMeta)
                    .xSmall
                    .muted,
              ]),
            ),
            if (t.isStarting.value)
              SizedBox(width: 16, height: 16, child: CircularProgressIndicator(size: 16))
            else
              Icon(LucideIcons.chevronRight, size: 16),
          ]),
        ),
      ),
    Gap(10),
    Button.ghost(
      onPressed: () => launchUrlString('https://bikecontrol.app/blog/virtual-shifting-with-and-without-bikecontrol/', mode: LaunchMode.externalApplication),
      child: Row(children: [
        Icon(LucideIcons.bookOpen, size: 15),
        Gap(8),
        Flexible(child: Text(context.i18n.onboardingTrainerHowItWorks).small),
        Gap(6),
        Icon(LucideIcons.externalLink, size: 13),
      ]),
    ),
  ]);
}
