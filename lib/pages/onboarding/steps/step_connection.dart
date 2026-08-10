import 'package:bike_control/pages/onboarding/widgets/onboarding_theme.dart';
import 'package:bike_control/bluetooth/devices/trainer_connection.dart';
import 'package:bike_control/pages/onboarding/onboarding_app_guides.dart';
import 'package:bike_control/pages/onboarding/onboarding_methods.dart';
import 'package:bike_control/pages/onboarding/widgets/onboarding_group_label.dart';
import 'package:bike_control/utils/i18n_extension.dart';
import 'package:bike_control/utils/keymap/apps/supported_app.dart';
import 'package:bike_control/utils/requirements/multi.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:url_launcher/url_launcher_string.dart';

const _success = Color(0xFF22C55E);
const _warning = Color(0xFFF59E0B);

/// One design-language method tile: icon square, title + badge, description,
/// optional feature checks, radio check-dot on the right. Selection state is
/// the method's real enabled state — toggling writes the same settings the
/// Trainer Connections tiles do (see onboarding_methods.dart).
class _MethodTile extends StatelessWidget {
  const _MethodTile({
    required this.icon,
    required this.title,
    required this.description,
    required this.enabled,
    required this.onToggle,
    this.connection,
    this.appName = '',
    this.badge,
    this.badgeIsPrimary = false,
    this.features = const [],
    this.disabled = false,
    this.footNote,
  });

  final IconData icon;
  final String title;
  final String description;
  final bool enabled;
  final VoidCallback onToggle;
  final TrainerConnection? connection;
  final String appName;
  final String? badge;
  final bool badgeIsPrimary;
  final List<String> features;
  final bool disabled;
  final String? footNote;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final on = enabled && !disabled;
    return Opacity(
      opacity: disabled ? 0.55 : 1,
      child: Button.ghost(
        style: ButtonStyle.ghost().withPadding(padding: EdgeInsets.zero),
        onPressed: disabled ? null : onToggle,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            border: Border.all(color: on ? onboardingAccent(context) : scheme.border, width: 1.5),
            borderRadius: BorderRadius.circular(12),
            color: scheme.card,
          ),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(11),
                color: on ? onboardingAccent(context) : scheme.muted,
              ),
              child: Icon(icon, size: 20, color: on ? onboardingOnAccent : null),
            ),
            Gap(12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Text(title).small.semiBold,
                  if (badge != null) ...[
                    Gap(7),
                    if (badgeIsPrimary) PrimaryBadge(child: Text(badge!)) else SecondaryBadge(child: Text(badge!)),
                  ],
                ]),
                Gap(4),
                Text(description).xSmall.muted,
                for (final f in features)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Row(children: [
                      Icon(LucideIcons.check, size: 13, color: _success),
                      Gap(7),
                      Text(f).xSmall,
                    ]),
                  ),
                if (footNote != null) ...[
                  Gap(8),
                  Row(children: [
                    Icon(LucideIcons.info, size: 14, color: scheme.mutedForeground),
                    Gap(7),
                    Expanded(child: Text(footNote!).xSmall.muted),
                  ]),
                ],
                // Live status: enabled is just the pref — show whether the
                // trainer app is actually connected through this method.
                if (on && connection != null)
                  AnimatedBuilder(
                    animation: Listenable.merge([connection!.isConnected, connection!.isStarted]),
                    builder: (context, _) {
                      final isConnected = connection!.isConnected.value;
                      return Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Row(children: [
                          Container(
                            width: 7,
                            height: 7,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: isConnected ? _success : Theme.of(context).colorScheme.mutedForeground,
                            ),
                          ),
                          Gap(7),
                          isConnected
                              ? DefaultTextStyle.merge(
                                  style: const TextStyle(color: _success),
                                  child: Text(context.i18n.onboardingDeviceConnected).xSmall.semiBold,
                                )
                              : Text(context.i18n.onboardingSummaryWaitingFor(appName)).xSmall.muted,
                        ]),
                      );
                    },
                  ),
              ]),
            ),
            Gap(10),
            Container(
              width: 20,
              height: 20,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: on ? onboardingAccent(context) : null,
                border: on ? null : Border.all(color: scheme.border, width: 2),
              ),
              child: on ? Icon(LucideIcons.check, size: 12, color: onboardingOnAccent) : null,
            ),
          ]),
        ),
      ),
    );
  }
}

Widget _slotRow(BuildContext context, IconData icon, String slot, String entryName, {required bool first}) {
  final scheme = Theme.of(context).colorScheme;
  return Container(
    padding: const EdgeInsets.symmetric(vertical: 7),
    decoration: first
        ? null
        : BoxDecoration(border: Border(top: BorderSide(color: scheme.border, width: 0.5))),
    child: Row(children: [
      Icon(icon, size: 15, color: onboardingAccent(context)),
      Gap(9),
      Expanded(child: Text(slot).xSmall.semiBold),
      Flexible(
        child: Text(entryName, overflow: TextOverflow.ellipsis, maxLines: 1).xSmall.muted,
      ),
    ]),
  );
}

Widget onboardingConnectionBody(
  BuildContext context, {
  required SupportedApp app,
  required Target target,
  required bool hasTrainer,
  required String? trainerName,
  required VoidCallback onUpdate,
}) {
  final guide = onboardingGuideFor(context, app);
  final scheme = Theme.of(context).colorScheme;
  final bridgeEntry = '${trainerName ?? ''} - BikeControl';

  Widget methodTile(OnboardingMethod method) {
    final enabled = onboardingMethodEnabled(method, app);
    final available = onboardingMethodAvailable(method);
    final connection = onboardingMethodConnection(method, app);
    void toggle() => setOnboardingMethodEnabled(context, method, app, !enabled, onUpdate: onUpdate);
    return switch (method) {
      OnboardingMethod.network => _MethodTile(
          icon: LucideIcons.wifi,
          title: context.i18n.onboardingMethodNetwork,
          badge: context.i18n.recommended,
          badgeIsPrimary: true,
          description: context.i18n.onboardingMethodNetworkDesc(app.name),
          enabled: enabled,
          connection: connection,
          appName: app.name,
          onToggle: toggle,
        ),
      OnboardingMethod.bluetooth => _MethodTile(
          icon: LucideIcons.bluetooth,
          title: context.i18n.onboardingMethodBluetooth,
          badge: context.i18n.onboardingMethodBluetoothBadge,
          description: context.i18n.onboardingMethodBluetoothDesc(app.name),
          enabled: enabled,
          connection: connection,
          appName: app.name,
          onToggle: toggle,
        ),
      OnboardingMethod.local => _MethodTile(
          icon: LucideIcons.keyboard,
          title: context.i18n.onboardingMethodLocal,
          badge: context.i18n.onboardingMethodLocalBadge,
          description: context.i18n.onboardingMethodLocalDesc,
          features: [
            context.i18n.onboardingMethodLocalFeature1,
            context.i18n.onboardingMethodLocalFeature2,
            context.i18n.onboardingMethodLocalFeature3,
          ],
          enabled: enabled,
          connection: connection,
          appName: app.name,
          disabled: !available,
          footNote: available ? null : context.i18n.onboardingMethodLocalIosNote,
          onToggle: toggle,
        ),
    };
  }

  return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text(context.i18n.onboardingConnectionTitle(app.name)).h4,
    Gap(6),
    Text(target == Target.thisDevice
            ? context.i18n.onboardingConnectionSubtitleLocal(app.name)
            : context.i18n.onboardingConnectionSubtitleNetwork(app.name))
        .small
        .muted,
    Gap(18),
    OnboardingGroupLabel(context.i18n.onboardingConnectionMethods),
    for (final method in OnboardingMethod.values)
      if (onboardingMethodVisible(method, app))
        Padding(padding: const EdgeInsets.only(bottom: 10), child: methodTile(method)),
    Gap(10),
    OnboardingGroupLabel(context.i18n.onboardingThenInApp(app.name)),
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
                decoration: BoxDecoration(shape: BoxShape.circle, color: onboardingAccent(context)),
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
      OnboardingGroupLabel(context.i18n.onboardingPairAsTrainer),
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          border: Border.all(color: onboardingAccent(context), width: 1.5),
          borderRadius: BorderRadius.circular(12),
          color: onboardingAccent(context).withValues(alpha: 0.06),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(context.i18n.onboardingPairAsTrainerBody(app.name)).small,
          Gap(12),
          Container(
            padding: const EdgeInsets.all(11),
            decoration: BoxDecoration(
                color: scheme.card, border: Border.all(color: scheme.border), borderRadius: BorderRadius.circular(10)),
            child: Row(children: [
              Icon(LucideIcons.radio, size: 20, color: onboardingAccent(context)),
              Gap(12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(bridgeEntry).small.semiBold,
                  Text(context.i18n.onboardingVirtualTrainerGears('${app.virtualGearAmount}')).xSmall.muted,
                ]),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(6),
                  color: _success.withValues(alpha: 0.12),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Container(
                    width: 7,
                    height: 7,
                    decoration: const BoxDecoration(shape: BoxShape.circle, color: _success),
                  ),
                  Gap(5),
                  DefaultTextStyle.merge(
                    style: const TextStyle(color: _success),
                    child: Text(context.i18n.onboardingLive).xSmall.semiBold,
                  ),
                ]),
              ),
            ]),
          ),
          Gap(12),
          DefaultTextStyle.merge(
            style: TextStyle(letterSpacing: 0.8, color: scheme.mutedForeground),
            child: Text(context.i18n.onboardingSelectItFor.toUpperCase()).xSmall.semiBold,
          ),
          Gap(4),
          _slotRow(context, LucideIcons.zap, context.i18n.onboardingSlotPower, bridgeEntry, first: true),
          _slotRow(context, LucideIcons.slidersHorizontal, context.i18n.onboardingSlotControllable, bridgeEntry,
              first: false),
          _slotRow(context, LucideIcons.refreshCw, context.i18n.onboardingSlotCadence, bridgeEntry, first: false),
          Gap(12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              color: _warning.withValues(alpha: 0.12),
              border: Border.all(color: _warning.withValues(alpha: 0.5)),
            ),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(LucideIcons.triangleAlert, size: 16, color: _warning),
              Gap(10),
              Expanded(
                child: Text(context.i18n.onboardingPairAsTrainerWarning(trainerName ?? '', app.name)).xSmall,
              ),
            ]),
          ),
        ]),
      ),
    ],
  ]);
}
