import 'package:bike_control/pages/onboarding/onboarding_models.dart';
import 'package:bike_control/utils/core.dart';
import 'package:bike_control/utils/i18n_extension.dart';
import 'package:bike_control/utils/keymap/apps/bike_control.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

const double kOnboardingDesktopBreakpoint = 800;
const double kOnboardingBodyMaxWidth = 640;

String onboardingStepLabel(BuildContext context, OnboardingStep step) => switch (step) {
      OnboardingStep.app => context.i18n.onboardingStepApp,
      OnboardingStep.where => context.i18n.onboardingStepWhere,
      OnboardingStep.controller => context.i18n.onboardingStepController,
      OnboardingStep.virtualShifting => context.i18n.onboardingStepVs,
      OnboardingStep.connection => context.i18n.onboardingStepConnection,
      OnboardingStep.done => context.i18n.onboardingStepDone,
    };

String onboardingStepSub(BuildContext context, OnboardingStep step) => switch (step) {
      OnboardingStep.app => context.i18n.onboardingStepAppSub,
      OnboardingStep.where => context.i18n.onboardingStepWhereSub,
      OnboardingStep.controller => context.i18n.onboardingStepControllerSub,
      OnboardingStep.virtualShifting => context.i18n.onboardingStepVsSub,
      OnboardingStep.connection => context.i18n.onboardingStepConnectionSub,
      OnboardingStep.done => context.i18n.onboardingStepDoneSub,
    };

/// Pure shell — mobile: header + progress bar + body + sticky footer;
/// desktop (>=800): left step rail + centred column + right-aligned footer.
/// Kept as a top-level function so snapshot tests can render any state.
Widget onboardingShell(
  BuildContext context, {
  required OnboardingStep step,
  required Widget body,
  required List<Widget> footerActions,
  VoidCallback? onBack,
  VoidCallback? onSkip,
  required VoidCallback onHelp,
}) {
  return LayoutBuilder(
    builder: (context, constraints) {
      final desktop = constraints.maxWidth >= kOnboardingDesktopBreakpoint;
      final scrolledBody = SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: desktop
            ? Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: kOnboardingBodyMaxWidth), child: body))
            : body,
      );

      if (!desktop) {
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: Row(
                children: [
                  if (onBack != null) IconButton.ghost(icon: Icon(LucideIcons.arrowLeft), onPressed: onBack),
                  Image.asset('icon.png', width: 30, height: 30),
                  Expanded(
                    child: Text(
                      context.i18n.onboardingStepOf('${step.index + 1}', '${OnboardingStep.values.length}'),
                      textAlign: TextAlign.center,
                    ).xSmall.muted,
                  ),
                  if (onSkip != null) GhostButton(onPressed: onSkip, child: Text(context.i18n.onboardingSkip)),
                  GhostButton(
                    onPressed: onHelp,
                    child: Row(children: [Icon(LucideIcons.lifeBuoy, size: 15), Gap(5), Text(context.i18n.onboardingHelp)]),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
              child: Row(
                children: [
                  for (var i = 0; i < OnboardingStep.values.length; i++) ...[
                    if (i > 0) Gap(4),
                    Expanded(
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 250),
                        height: 4,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(3),
                          color: i <= step.index
                              ? Theme.of(context).colorScheme.primary
                              : Theme.of(context).colorScheme.border,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Expanded(child: scrolledBody),
            if (footerActions.isNotEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.card,
                  border: Border(top: BorderSide(color: Theme.of(context).colorScheme.border)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < footerActions.length; i++) ...[if (i > 0) Gap(8), footerActions[i]],
                  ],
                ),
              ),
          ],
        );
      }

      return Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            width: 268,
            padding: const EdgeInsets.fromLTRB(14, 18, 14, 14),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.muted,
              border: Border(right: BorderSide(color: Theme.of(context).colorScheme.border)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(children: [
                  Image.asset('icon.png', width: 30, height: 30),
                  Gap(10),
                  Text('BikeControl').semiBold,
                ]),
                Gap(18),
                for (final s in OnboardingStep.values) _railStep(context, s, step),
                const Spacer(),
                SecondaryButton(
                  onPressed: onHelp,
                  child: Row(children: [
                    Icon(LucideIcons.lifeBuoy, size: 16),
                    Gap(9),
                    Expanded(child: Text(context.i18n.onboardingHelpAndSupport)),
                  ]),
                ),
              ],
            ),
          ),
          Expanded(
            child: Column(
              children: [
                Expanded(child: scrolledBody),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.card,
                    border: Border(top: BorderSide(color: Theme.of(context).colorScheme.border)),
                  ),
                  child: Row(
                    children: [
                      if (onBack != null) GhostButton(onPressed: onBack, child: Text(context.i18n.onboardingBack)),
                      if (onSkip != null) ...[Gap(8), GhostButton(onPressed: onSkip, child: Text(context.i18n.onboardingSkip))],
                      const Spacer(),
                      for (var i = 0; i < footerActions.length; i++) ...[if (i > 0) Gap(10), footerActions[i]],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    },
  );
}

Widget _railStep(BuildContext context, OnboardingStep s, OnboardingStep current) {
  final done = s.index < current.index;
  final active = s == current;
  final scheme = Theme.of(context).colorScheme;
  return Container(
    margin: const EdgeInsets.only(bottom: 2),
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(8),
      color: active ? scheme.card : null,
      border: Border.all(color: active ? scheme.border : const Color(0x00000000)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 24,
          height: 24,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: done
                ? const Color(0xFF22C55E)
                : active
                    ? scheme.primary
                    : scheme.border,
          ),
          child: done
              ? Icon(LucideIcons.check, size: 13, color: const Color(0xFFFFFFFF))
              : DefaultTextStyle.merge(
                  style: TextStyle(color: active ? const Color(0xFFFFFFFF) : scheme.mutedForeground),
                  child: Text('${s.index + 1}').xSmall.semiBold,
                ),
        ),
        Gap(12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(onboardingStepLabel(context, s)).small.semiBold,
              Text(onboardingStepSub(context, s)).xSmall.muted,
            ],
          ),
        ),
      ],
    ),
  );
}

class OnboardingPage extends StatefulWidget {
  const OnboardingPage({super.key});

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  OnboardingStep _step = OnboardingStep.app;

  bool get _selfHosted => core.settings.getTrainerApp() is BikeControl;

  void _next() => setState(() => _step = onboardingNextStep(_step, appIsSelfHosted: _selfHosted));
  void _back() => setState(() => _step = onboardingPreviousStep(_step, appIsSelfHosted: _selfHosted));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      child: SafeArea(
        child: onboardingShell(
          context,
          step: _step,
          body: const SizedBox(), // per-step bodies land in Tasks 5-12
          footerActions: [
            PrimaryButton(onPressed: _next, child: Text(context.i18n.onboardingContinue)),
          ],
          onBack: _step == OnboardingStep.app ? null : _back,
          onHelp: () {}, // wired in Task 3
        ),
      ),
    );
  }
}
