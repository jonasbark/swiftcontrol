import 'package:bike_control/utils/i18n_extension.dart';
import 'package:bike_control/utils/keymap/apps/supported_app.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

Widget onboardingDoneBody(BuildContext context,
    {required SupportedApp app,
    required String? controllerName,
    required String? trainerName,
    required bool reduceMotion,
    required bool showTestMode}) {
  const success = Color(0xFF22C55E);
  final rows = <(IconData, String, String)>[
    if (controllerName != null) (LucideIcons.gamepad2, controllerName, context.i18n.onboardingDeviceConnected),
    (LucideIcons.monitor, app.name, context.i18n.onboardingSummaryReady),
    if (trainerName != null) (LucideIcons.bike, trainerName, context.i18n.onboardingSummaryBridged),
  ];
  return Column(crossAxisAlignment: CrossAxisAlignment.center, children: [
    Gap(8),
    _SuccessBurst(reduceMotion: reduceMotion),
    Gap(14),
    Text(context.i18n.onboardingDoneTitle).h4,
    Gap(8),
    Text(
      trainerName != null
          ? context.i18n.onboardingDoneSubtitleBridged(controllerName ?? context.i18n.onboardingYourController, app.name)
          : context.i18n.onboardingDoneSubtitle(controllerName ?? context.i18n.onboardingYourController, app.name),
      textAlign: TextAlign.center,
    ).small.muted,
    Gap(18),
    for (final (icon, title, sub) in rows)
      Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(color: success.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
        child: Row(children: [
          Icon(icon, size: 17, color: success),
          Gap(11),
          Expanded(child: Text(title).small.semiBold),
          Text(sub).xSmall.muted,
        ]),
      ),
    if (showTestMode) ...[
      Gap(10),
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          border: Border.all(color: const Color(0xFFF59E0B), width: 1.5),
          borderRadius: BorderRadius.circular(12),
          color: const Color(0x1AF59E0B),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(LucideIcons.flaskConical, size: 18, color: const Color(0xFFF59E0B)),
            Gap(9),
            Text(context.i18n.onboardingTestModeTitle).small.semiBold,
          ]),
          Gap(6),
          Text(trainerName != null ? context.i18n.onboardingTestModeBodyVs : context.i18n.onboardingTestModeBody).xSmall,
        ]),
      ),
    ],
  ]);
}

/// Green success circle shown at the top of the "done" step. Pops in with a
/// spring-like scale (mirrors [StageBadge] in `guided_operation_sheet.dart`)
/// unless [reduceMotion] is set, in which case it renders statically.
class _SuccessBurst extends StatelessWidget {
  const _SuccessBurst({required this.reduceMotion});
  final bool reduceMotion;

  @override
  Widget build(BuildContext context) {
    const success = Color(0xFF22C55E);
    final badge = Container(
      width: 84,
      height: 84,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: success,
        boxShadow: [BoxShadow(color: success.withValues(alpha: 0.35), blurRadius: 30, offset: const Offset(0, 10))],
      ),
      child: Icon(LucideIcons.check, size: 44, color: const Color(0xFFFFFFFF)),
    );
    if (reduceMotion) return badge;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.6, end: 1.0),
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutBack,
      builder: (context, scale, child) => Transform.scale(scale: scale, child: child),
      child: badge,
    );
  }
}
