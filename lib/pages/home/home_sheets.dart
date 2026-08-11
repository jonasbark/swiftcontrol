import 'package:bike_control/pages/onboarding/onboarding_app_guides.dart';
import 'package:bike_control/pages/onboarding/onboarding_models.dart';
import 'package:bike_control/pages/onboarding/onboarding_sheets.dart';
import 'package:bike_control/utils/core.dart';
import 'package:bike_control/utils/i18n_extension.dart';
import 'package:bike_control/utils/keymap/apps/supported_app.dart';
import 'package:bike_control/widgets/guided_operation_sheet.dart';
import 'package:bike_control/widgets/scan.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:url_launcher/url_launcher_string.dart';

/// The instruction sheets a chain card's active step opens.
///
/// These deliberately route into content that already exists — the onboarding
/// help sheets and the per-app setup guides — rather than growing a second,
/// parallel help system that would drift out of sync with the first.

Widget _frame(BuildContext context, Widget child) {
  return Center(
    heightFactor: 1,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 520),
      child: Padding(padding: const EdgeInsets.all(20), child: child),
    ),
  );
}

/// Pairing a controller for the first time. The scanner is embedded rather than
/// described, so the next action is on screen instead of a page away.
Future<void> openControllerSetupSheet(BuildContext context) {
  return openSheet<void>(
    context: context,
    position: OverlayPosition.bottom,
    builder: (sheetContext) => _frame(
      sheetContext,
      Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          StageBadge(
            icon: LucideIcons.bluetooth,
            tone: Theme.of(sheetContext).colorScheme.primary,
            wash: Theme.of(sheetContext).colorScheme.primary.withValues(alpha: 0.1),
            reduceMotion: MediaQuery.of(sheetContext).disableAnimations,
          ),
          const Gap(14),
          Text(sheetContext.i18n.connectControllers).h4,
          const Gap(6),
          Text(sheetContext.i18n.chainStepControllerPairedHint).small.muted,
          const Gap(14),
          const ScanWidget(),
          const Gap(14),
          SizedBox(
            width: double.infinity,
            child: PrimaryButton(
              onPressed: () => closeSheet(sheetContext),
              child: Text(sheetContext.i18n.close),
            ),
          ),
        ],
      ),
    ),
  );
}

/// "Get your controller back" — the reconnect checklist. Routed on the card's
/// state, never on step wording, so a never-paired controller gets the pairing
/// flow above and a dropped one gets this.
Future<void> openControllerHelpSheet(BuildContext context) {
  return openOnboardingHelpSheet(context, OnboardingStep.controller);
}

Future<void> openTrainerHelpSheet(BuildContext context) {
  return openOnboardingHelpSheet(context, OnboardingStep.virtualShifting);
}

/// The per-app "then in {app}" guide — the same numbered steps, screenshots and
/// guide link the onboarding connection step shows. Falls back to the generic
/// connection help when no app has been chosen yet.
Future<void> openAppGuideSheet(BuildContext context) {
  final app = core.settings.getTrainerApp();
  if (app == null) return openOnboardingHelpSheet(context, OnboardingStep.connection);

  return openSheet<void>(
    context: context,
    position: OverlayPosition.bottom,
    builder: (sheetContext) => _frame(sheetContext, _AppGuide(app: app)),
  );
}

class _AppGuide extends StatelessWidget {
  const _AppGuide({required this.app});

  final SupportedApp app;

  @override
  Widget build(BuildContext context) {
    final guide = onboardingGuideFor(context, app);
    final scheme = Theme.of(context).colorScheme;
    final guideUrl = guide.guideUrl;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        StageBadge(
          icon: LucideIcons.monitor,
          tone: scheme.primary,
          wash: scheme.primary.withValues(alpha: 0.1),
          reduceMotion: MediaQuery.of(context).disableAnimations,
        ),
        const Gap(14),
        Text(context.i18n.onboardingThenInApp(app.name)).h4,
        const Gap(12),
        for (final (index, step) in guide.steps.indexed) ...[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(color: scheme.primary, shape: BoxShape.circle),
                alignment: Alignment.center,
                child: Text(
                  '${index + 1}',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white),
                ),
              ),
              const Gap(12),
              Expanded(child: Text(step).small),
            ],
          ),
          const Gap(12),
        ],
        if (guideUrl != null) ...[
          const Gap(2),
          SizedBox(
            width: double.infinity,
            child: OutlineButton(
              onPressed: () => launchUrlString(guideUrl, mode: LaunchMode.externalApplication),
              trailing: const Icon(LucideIcons.externalLink, size: 14),
              child: Text(context.i18n.onboardingFullSetupGuide(app.name)),
            ),
          ),
          const Gap(8),
        ],
        SizedBox(
          width: double.infinity,
          child: PrimaryButton(
            onPressed: () => closeSheet(context),
            child: Text(context.i18n.close),
          ),
        ),
      ],
    );
  }
}
