# First-Run Onboarding Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A six-step guided setup wizard (trainer app → where it runs → controller → virtual shifting → connection → ready) shown on fresh installs and re-runnable from the menu, per `docs/superpowers/specs/2026-08-09-onboarding-design.md`.

**Architecture:** One full-screen route (`OnboardingPage`) pushed over `Navigation`, holding an `enum` step machine. Step bodies are pure functions of explicit state (the `sramGuidedBody` pattern) so PNG-snapshot tests render production UI. A `LayoutBuilder` breakpoint at 800 switches between the mobile shell (progress bar + sticky footer) and desktop shell (left step rail + centred 640px column). All persistence goes through the existing settings paths; two small behavior-preserving refactors extract shared logic (app/target selection side-effects, connection-method tiles) so wizard and settings pages share one implementation.

**Tech Stack:** Flutter + shadcn_flutter 0.0.52 (`Scaffold`, `SelectableCard`, `openSheet`/`openDrawer`, text extensions `.small/.muted/.semibold/.h4`), `core` singleton (`package:bike_control/utils/core.dart`), intl_utils ARB l10n, PNG snapshot harness (`test/widget_snapshot.dart`).

## Global Constraints

- UI is **shadcn_flutter**, not Material: `PrimaryButton`/`SecondaryButton`/`GhostButton`/`Button.ghost`, `Gap`, `SelectableCard`, `openSheet`/`openDrawer`/`closeSheet` (`OverlayPosition.bottom` / `.end`). Never `GestureDetector`+`MouseRegion` for tappables.
- Never swallow exceptions: every `catch` forwards `recordError(e, s, context: 'onboarding …')` (`recordError` is in `lib/main.dart`).
- L10n: add strings to `lib/i10n/intl_en.arb` ONLY (note the path spelling `i10n`), then run `flutter pub global run intl_utils:generate`. Never hand-edit `lib/gen/l10n.dart`. Access via `context.i18n.<key>` (`lib/utils/i18n_extension.dart`). Key prefix for new strings: `onboarding…`. No tests asserting l10n literals.
- Use the design's copy (quoted per task below) for all new strings.
- `screenshotMode` (`var screenshotMode = false;` in `lib/main.dart:34`) must suppress auto-showing the wizard.
- Auto-connect behavior in `lib/bluetooth/connection.dart` is UNCHANGED — no tap-to-pick, no queue suppression.
- Virtual-shifting Pro gating is UNCHANGED (`isProEnabledForCurrentDevice`; no `OrDidPurchaseOld` grandfathering) — the wizard only routes through existing gated pages.
- Navigation idiom: `context.push(Widget)` (extension in `lib/utils/i18n_extension.dart`); back is `Navigator.of(context).pop()`.
- Respect reduced motion: `MediaQuery.of(context).disableAnimations` threaded as `reduceMotion` (see `sram_setup_sheet.dart:131`).
- Commit style: `feat(onboarding): …` / `refactor: …` / `test(onboarding): …`. `docs/` is gitignored — plans/specs need `git add -f`; source under `lib/`/`test/` adds normally.
- Snapshot tests are PNG exports for human review (`build/snapshots/`), NOT golden comparisons. Run them standalone (`flutter test test/<file>` — do not co-run with integration tests). Always start snapshot test files with `await ensureSnapshotHarness();` (see `test/sram_states_snapshot_test.dart`).
- After each task: `flutter analyze lib test` must be clean for the files you touched.

---

### Task 1: Trigger plumbing — pref, decision function, Navigation hook, menu entry

**Files:**
- Create: `lib/pages/onboarding/onboarding_trigger.dart`
- Create: `lib/pages/onboarding/onboarding_page.dart` (placeholder)
- Modify: `lib/utils/settings/settings.dart` (add pref, near `getVirtualShiftingIntroSeen` at ~line 202)
- Modify: `lib/pages/navigation.dart:105-127` (`_checkAndShowChangelog`)
- Modify: `lib/widgets/menu.dart` (insert before the Logs `MenuButton` at ~line 251)
- Modify: `lib/i10n/intl_en.arb`
- Test: `test/onboarding_trigger_test.dart`

**Interfaces:**
- Consumes: `core.settings` prefs pattern, `getLastSeenVersion()` (settings.dart:332), `context.push`.
- Produces: `OnboardingTriggerAction decideOnboardingTrigger({required String? lastSeenVersion, required String? onboardingState})`; `Settings.getOnboardingState() → String?` / `setOnboardingState(String)` with constants `Settings.onboardingStatePending` / `Settings.onboardingStateCompleted`; `class OnboardingPage extends StatefulWidget { const OnboardingPage({super.key}); }`.

- [ ] **Step 1: Write the failing test**

```dart
// test/onboarding_trigger_test.dart
import 'package:bike_control/pages/onboarding/onboarding_trigger.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('fresh install, never triggered -> show', () {
    expect(
      decideOnboardingTrigger(lastSeenVersion: null, onboardingState: null),
      OnboardingTriggerAction.show,
    );
  });

  test('existing install, never triggered -> silently mark completed', () {
    expect(
      decideOnboardingTrigger(lastSeenVersion: '6.2.0', onboardingState: null),
      OnboardingTriggerAction.markCompleted,
    );
  });

  test('pending (quit mid-flow) -> show again, even though a version is now recorded', () {
    expect(
      decideOnboardingTrigger(lastSeenVersion: '6.3.0', onboardingState: 'pending'),
      OnboardingTriggerAction.show,
    );
  });

  test('completed -> none', () {
    expect(
      decideOnboardingTrigger(lastSeenVersion: '6.3.0', onboardingState: 'completed'),
      OnboardingTriggerAction.none,
    );
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/onboarding_trigger_test.dart`
Expected: FAIL — `onboarding_trigger.dart` doesn't exist.

- [ ] **Step 3: Implement the trigger decision + pref + placeholder page**

```dart
// lib/pages/onboarding/onboarding_trigger.dart
enum OnboardingTriggerAction { show, markCompleted, none }

/// Pure decision, unit-testable without SharedPreferences.
///
/// [onboardingState] is the raw `onboarding_state` pref: null (never
/// triggered), 'pending' (started, not finished) or 'completed'.
/// [lastSeenVersion] is null exactly on a fresh install — the changelog
/// mechanism ([Settings.setLastSeenVersion]) writes it on every launch.
/// The 'pending' check must come before the fresh-install check: after the
/// first launch a version is recorded, but a rider who quit mid-flow still
/// gets the wizard back.
OnboardingTriggerAction decideOnboardingTrigger({
  required String? lastSeenVersion,
  required String? onboardingState,
}) {
  if (onboardingState == 'completed') return OnboardingTriggerAction.none;
  if (onboardingState == 'pending') return OnboardingTriggerAction.show;
  return lastSeenVersion == null
      ? OnboardingTriggerAction.show
      : OnboardingTriggerAction.markCompleted;
}
```

In `lib/utils/settings/settings.dart`, next to the `_virtualShiftingIntroSeenKey` block (~line 202), following the same idiom:

```dart
  static const String _onboardingStateKey = 'onboarding_state';
  static const String onboardingStatePending = 'pending';
  static const String onboardingStateCompleted = 'completed';

  /// First-run onboarding wizard state: null = never triggered,
  /// [onboardingStatePending] = started but not finished (re-shown on next
  /// launch), [onboardingStateCompleted] = finished or migrated existing
  /// install (only reachable via the "Setup guide" menu entry).
  String? getOnboardingState() {
    return prefs.getString(_onboardingStateKey);
  }

  Future<void> setOnboardingState(String state) async {
    await prefs.setString(_onboardingStateKey, state);
  }
```

Placeholder page (replaced in Task 2 — keep it minimal so the hook compiles):

```dart
// lib/pages/onboarding/onboarding_page.dart
import 'package:shadcn_flutter/shadcn_flutter.dart';

class OnboardingPage extends StatefulWidget {
  const OnboardingPage({super.key});

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  @override
  Widget build(BuildContext context) {
    return const Scaffold(child: SizedBox());
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/onboarding_trigger_test.dart`
Expected: 4 PASS.

- [ ] **Step 5: Hook into Navigation**

In `lib/pages/navigation.dart` `_checkAndShowChangelog()` (line ~105), after reading `lastSeenVersion` and the Windows IAP block, BEFORE `ChangelogDialog.showIfNeeded`:

```dart
      final onboardingAction = decideOnboardingTrigger(
        lastSeenVersion: lastSeenVersion,
        onboardingState: core.settings.getOnboardingState(),
      );
      if (onboardingAction == OnboardingTriggerAction.markCompleted) {
        await core.settings.setOnboardingState(Settings.onboardingStateCompleted);
      } else if (onboardingAction == OnboardingTriggerAction.show && !screenshotMode) {
        await core.settings.setOnboardingState(Settings.onboardingStatePending);
        if (mounted) {
          await context.push(OnboardingPage());
        }
      }
```

Add imports: `package:bike_control/pages/onboarding/onboarding_page.dart`, `package:bike_control/pages/onboarding/onboarding_trigger.dart`, `package:bike_control/utils/settings/settings.dart` (for the constants; `screenshotMode` comes from the existing `main.dart` import at navigation.dart:6). The existing `catch` already logs; keep the whole block inside the existing `try`.

- [ ] **Step 6: Menu entry**

In `lib/widgets/menu.dart`, inside `BKMenuButton`'s dropdown, directly BEFORE the Logs `MenuButton` (~line 251):

```dart
            MenuButton(
              leading: Icon(Icons.tips_and_updates_outlined),
              child: Text(context.i18n.onboardingMenuEntry),
              onPressed: (c) async {
                await context.push(OnboardingPage());
              },
            ),
```

ARB (alphabetical-ish placement, flat key):

```json
  "onboardingMenuEntry": "Setup guide",
```

Run: `flutter pub global run intl_utils:generate`

- [ ] **Step 7: Verify + commit**

Run: `flutter analyze lib/pages/onboarding lib/pages/navigation.dart lib/widgets/menu.dart lib/utils/settings/settings.dart test/onboarding_trigger_test.dart` → clean.
Run: `flutter test test/onboarding_trigger_test.dart` → PASS.

```bash
git add lib/pages/onboarding lib/pages/navigation.dart lib/widgets/menu.dart lib/utils/settings/settings.dart lib/i10n/intl_en.arb lib/gen test/onboarding_trigger_test.dart
git commit -m "feat(onboarding): trigger wizard on fresh installs, add Setup guide menu entry"
```

---

### Task 2: Responsive shell — step enum, progress bar / step rail, footer

**Files:**
- Create: `lib/pages/onboarding/onboarding_models.dart`
- Modify: `lib/pages/onboarding/onboarding_page.dart` (replace placeholder)
- Modify: `lib/i10n/intl_en.arb`
- Test: `test/onboarding_models_test.dart`, `test/onboarding_snapshot_test.dart`

**Interfaces:**
- Consumes: shadcn `Scaffold`, `GhostButton`, `Button.ghost`, `Gap`, text extensions; `LucideIcons.lifeBuoy`, `LucideIcons.arrowLeft`.
- Produces:
  - `enum OnboardingStep { app, where, controller, virtualShifting, connection, done }`
  - `enum ControllerPhase { permission, scanning, empty, list }`
  - `OnboardingStep onboardingNextStep(OnboardingStep step, {required bool appIsSelfHosted})`
  - `OnboardingStep onboardingPreviousStep(OnboardingStep step, {required bool appIsSelfHosted})`
  - `Widget onboardingShell(BuildContext context, {required OnboardingStep step, required Widget body, required List<Widget> footerActions, VoidCallback? onBack, VoidCallback? onSkip, required VoidCallback onHelp})` — later tasks ONLY swap the `body`/`footerActions` per step; the shell signature is stable.
  - `String onboardingStepLabel(BuildContext context, OnboardingStep step)` and `String onboardingStepSub(BuildContext context, OnboardingStep step)`.

- [ ] **Step 1: Write the failing model test**

```dart
// test/onboarding_models_test.dart
import 'package:bike_control/pages/onboarding/onboarding_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('next advances linearly', () {
    expect(onboardingNextStep(OnboardingStep.app, appIsSelfHosted: false), OnboardingStep.where);
    expect(onboardingNextStep(OnboardingStep.connection, appIsSelfHosted: false), OnboardingStep.done);
  });

  test('self-hosted app (BikeControl) skips the where step in both directions', () {
    expect(onboardingNextStep(OnboardingStep.app, appIsSelfHosted: true), OnboardingStep.controller);
    expect(onboardingPreviousStep(OnboardingStep.controller, appIsSelfHosted: true), OnboardingStep.app);
  });

  test('done does not advance, app does not go back', () {
    expect(onboardingNextStep(OnboardingStep.done, appIsSelfHosted: false), OnboardingStep.done);
    expect(onboardingPreviousStep(OnboardingStep.app, appIsSelfHosted: false), OnboardingStep.app);
  });
}
```

- [ ] **Step 2: Run it — FAIL** (`flutter test test/onboarding_models_test.dart`, file missing)

- [ ] **Step 3: Implement models**

```dart
// lib/pages/onboarding/onboarding_models.dart
enum OnboardingStep { app, where, controller, virtualShifting, connection, done }

/// Sub-phases of the controller step. "Connected" is not a phase — it is
/// derived live from `core.connection.controllerDevices` so auto-connect can
/// flip the UI at any moment.
enum ControllerPhase { permission, scanning, empty, list }

/// BikeControl-as-trainer-app is self-hosted, so "where does it run" is
/// meaningless — the settings side of this rule lives in
/// applyTrainerAppSelection (Task 4), which pins Target.thisDevice.
OnboardingStep onboardingNextStep(OnboardingStep step, {required bool appIsSelfHosted}) {
  if (step == OnboardingStep.done) return OnboardingStep.done;
  var next = OnboardingStep.values[step.index + 1];
  if (next == OnboardingStep.where && appIsSelfHosted) {
    next = OnboardingStep.controller;
  }
  return next;
}

OnboardingStep onboardingPreviousStep(OnboardingStep step, {required bool appIsSelfHosted}) {
  if (step == OnboardingStep.app) return OnboardingStep.app;
  var prev = OnboardingStep.values[step.index - 1];
  if (prev == OnboardingStep.where && appIsSelfHosted) {
    prev = OnboardingStep.app;
  }
  return prev;
}
```

- [ ] **Step 4: Run — PASS**, then build the shell

Replace `onboarding_page.dart`:

```dart
// lib/pages/onboarding/onboarding_page.dart
import 'package:bike_control/pages/onboarding/onboarding_models.dart';
import 'package:bike_control/utils/core.dart';
import 'package:bike_control/utils/i18n_extension.dart';
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
                  Image.asset('assets/icon.png', width: 30, height: 30),
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
                  Image.asset('assets/icon.png', width: 30, height: 30),
                  Gap(10),
                  Text('BikeControl').semibold,
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
              : Text('${s.index + 1}').xSmall.semibold.withColor(active ? const Color(0xFFFFFFFF) : scheme.mutedForeground),
        ),
        Gap(12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(onboardingStepLabel(context, s)).small.semibold,
              Text(onboardingStepSub(context, s)).xSmall.muted,
            ],
          ),
        ),
      ],
    ),
  );
}
```

Note: if `.withColor(...)` does not exist in shadcn's text extensions, use `DefaultTextStyle.merge(style: TextStyle(color: ...), child: Text(...))` — check how `sram_setup_sheet.dart` colors text and copy that idiom.

The page state hosts the shell and wires navigation (bodies are placeholders until their tasks land):

```dart
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
```

(`BikeControl` the app class: `import 'package:bike_control/utils/keymap/apps/bike_control.dart';` — verify the actual file name with grep, it's the class used in `configuration.dart`'s `selectedApp is BikeControl` check.)

- [ ] **Step 5: ARB strings** (design copy)

```json
  "onboardingStepOf": "Step {current} of {total}",
  "@onboardingStepOf": {"placeholders": {"current": {"type": "String"}, "total": {"type": "String"}}},
  "onboardingStepApp": "Trainer app",
  "onboardingStepAppSub": "Who you ride with",
  "onboardingStepWhere": "Where it runs",
  "onboardingStepWhereSub": "This or another device",
  "onboardingStepController": "Controller",
  "onboardingStepControllerSub": "Find and connect",
  "onboardingStepVs": "Virtual shifting",
  "onboardingStepVsSub": "Optional",
  "onboardingStepConnection": "Connection",
  "onboardingStepConnectionSub": "Link the app",
  "onboardingStepDone": "Ready",
  "onboardingStepDoneSub": "Test and ride",
  "onboardingHelp": "Help",
  "onboardingHelpAndSupport": "Help & Support",
  "onboardingSkip": "Skip",
  "onboardingBack": "Back",
  "onboardingContinue": "Continue",
```

Run: `flutter pub global run intl_utils:generate`

- [ ] **Step 6: Snapshot test of both shells**

```dart
// test/onboarding_snapshot_test.dart
import 'package:bike_control/pages/onboarding/onboarding_models.dart';
import 'package:bike_control/pages/onboarding/onboarding_page.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import 'widget_snapshot.dart';

Future<void> main() async {
  await ensureSnapshotHarness();

  Widget shell(BuildContext context, {required OnboardingStep step}) => SizedBox(
        height: 720,
        child: onboardingShell(
          context,
          step: step,
          body: const Text('body placeholder'),
          footerActions: [PrimaryButton(onPressed: () {}, child: const Text('Continue'))],
          onBack: step == OnboardingStep.app ? null : () {},
          onHelp: () {},
        ),
      );

  testWidgets('shell mobile', (tester) async {
    await captureWidget(tester, name: 'onboarding_shell_mobile', width: 380,
        builder: (c) => shell(c, step: OnboardingStep.controller));
  });

  testWidgets('shell desktop', (tester) async {
    await captureWidget(tester, name: 'onboarding_shell_desktop', width: 1000,
        builder: (c) => shell(c, step: OnboardingStep.controller));
  });
}
```

Run: `flutter test test/onboarding_snapshot_test.dart` → PASS; open `build/snapshots/onboarding_shell_mobile-en.png` and `…desktop-en.png` and visually confirm: mobile = header + 6-segment progress + footer; desktop = 268px rail with done/active/upcoming + right-aligned footer.

- [ ] **Step 7: Commit**

```bash
git add lib/pages/onboarding lib/i10n/intl_en.arb lib/gen test/onboarding_models_test.dart test/onboarding_snapshot_test.dart
git commit -m "feat(onboarding): responsive wizard shell with step rail and progress bar"
```

---

### Task 3: Help sheet + permission-denied sheet

**Files:**
- Create: `lib/pages/onboarding/onboarding_sheets.dart`
- Modify: `lib/pages/onboarding/onboarding_page.dart` (wire `onHelp`)
- Modify: `lib/i10n/intl_en.arb`
- Test: extend `test/onboarding_snapshot_test.dart`

**Interfaces:**
- Consumes: `openSheet`/`closeSheet` (shadcn), `StageBadge` (`lib/widgets/guided_operation_sheet.dart:43` — `StageBadge({icon, tone, wash, reduceMotion})`), `helpArticleFor` (`lib/utils/help_article.dart`), `MarkdownPage` (`lib/pages/markdown.dart`, opened like `menu.dart:271-281`), the support-chat entry (open it exactly the way `lib/widgets/ui/help_button.dart` does around lines 94-110 — read that file and copy the working invocation), `launchUrlString` (`package:url_launcher/url_launcher_string.dart`).
- Produces:
  - `Future<void> openOnboardingHelpSheet(BuildContext context, OnboardingStep step)`
  - `Future<bool?> openPermissionDeniedSheet(BuildContext context)` — resolves `true` = "continue anyway", `false` = "allow Bluetooth" (retry), `null` = dismissed.
  - `Widget onboardingHelpSheetBody(BuildContext context, {required OnboardingStep step, required VoidCallback onClose})` and `Widget permissionDeniedSheetBody(BuildContext context, {required VoidCallback onContinueAnyway, required VoidCallback onAllow})` — pure bodies for snapshots.

- [ ] **Step 1: Implement bodies + openers**

```dart
// lib/pages/onboarding/onboarding_sheets.dart
import 'package:bike_control/pages/onboarding/onboarding_models.dart';
import 'package:bike_control/utils/core.dart';
import 'package:bike_control/utils/help_article.dart';
import 'package:bike_control/utils/i18n_extension.dart';
import 'package:bike_control/widgets/guided_operation_sheet.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:url_launcher/url_launcher_string.dart';

({String title, String body}) _stepHelp(BuildContext context, OnboardingStep step) => switch (step) {
      OnboardingStep.app => (title: context.i18n.onboardingHelpAppTitle, body: context.i18n.onboardingHelpAppBody),
      OnboardingStep.where => (title: context.i18n.onboardingHelpWhereTitle, body: context.i18n.onboardingHelpWhereBody),
      OnboardingStep.controller =>
        (title: context.i18n.onboardingHelpControllerTitle, body: context.i18n.onboardingHelpControllerBody),
      OnboardingStep.virtualShifting => (title: context.i18n.onboardingHelpVsTitle, body: context.i18n.onboardingHelpVsBody),
      OnboardingStep.connection =>
        (title: context.i18n.onboardingHelpConnectionTitle, body: context.i18n.onboardingHelpConnectionBody),
      OnboardingStep.done => (title: context.i18n.onboardingHelpDoneTitle, body: context.i18n.onboardingHelpDoneBody),
    };

Widget onboardingHelpSheetBody(BuildContext context, {required OnboardingStep step, required VoidCallback onClose}) {
  final h = _stepHelp(context, step);
  final scheme = Theme.of(context).colorScheme;
  final reduceMotion = MediaQuery.of(context).disableAnimations;
  final article = helpArticleFor(
    context,
    controller: core.connection.controllerDevices.where((d) => d.isConnected).firstOrNull,
    app: core.settings.getTrainerApp(),
  );
  return Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      StageBadge(icon: LucideIcons.lifeBuoy, tone: scheme.primary, wash: scheme.primary.withValues(alpha: 0.1), reduceMotion: reduceMotion),
      Gap(14),
      Text(context.i18n.onboardingHelpSheetTitle).h4,
      Gap(6),
      Text(context.i18n.onboardingHelpSheetIntro).small.muted,
      Gap(14),
      // Contextual answer for the current step
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          border: Border.all(color: scheme.primary, width: 1.5),
          borderRadius: BorderRadius.circular(12),
          color: scheme.primary.withValues(alpha: 0.06),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [Text(h.title).small.semibold, Gap(4), Text(h.body).xSmall.muted],
        ),
      ),
      Gap(12),
      _channel(context, icon: LucideIcons.bookOpen, title: context.i18n.onboardingHelpGuides,
          onTap: () => launchUrlString(article?.url ?? 'https://bikecontrol.app/', mode: LaunchMode.externalApplication)),
      _channel(context, icon: LucideIcons.wrench, title: context.i18n.onboardingHelpTroubleshooting,
          onTap: () {
            onClose();
            openDrawer(context: context, position: OverlayPosition.bottom,
                builder: (c) => MarkdownPage(assetPath: 'TROUBLESHOOTING.md'));
          }),
      _channel(context, icon: LucideIcons.mail, title: context.i18n.onboardingHelpSupport,
          onTap: () {
            onClose();
            // Open the in-app support chat exactly as HelpButton does
            // (lib/widgets/ui/help_button.dart ~94-110) — copy that invocation.
          }),
      Gap(16),
      Align(alignment: Alignment.centerRight, child: PrimaryButton(onPressed: onClose, child: Text(context.i18n.onboardingHelpBackToSetup))),
    ],
  );
}

Widget _channel(BuildContext context, {required IconData icon, required String title, required VoidCallback onTap}) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Button.card(
      onPressed: onTap,
      child: Row(children: [
        Icon(icon, size: 18),
        Gap(12),
        Expanded(child: Text(title).small.semibold),
        Icon(LucideIcons.externalLink, size: 14),
      ]),
    ),
  );
}

Future<void> openOnboardingHelpSheet(BuildContext context, OnboardingStep step) {
  return openSheet<void>(
    context: context,
    position: OverlayPosition.bottom,
    builder: (sheetContext) => _sheetFrame(
      sheetContext,
      onboardingHelpSheetBody(sheetContext, step: step, onClose: () => closeSheet(sheetContext)),
    ),
  );
}

Widget permissionDeniedSheetBody(BuildContext context,
    {required VoidCallback onContinueAnyway, required VoidCallback onAllow}) {
  final reduceMotion = MediaQuery.of(context).disableAnimations;
  return Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      StageBadge(icon: LucideIcons.bluetoothOff, tone: const Color(0xFFDC2626),
          wash: const Color(0x1ADC2626), reduceMotion: reduceMotion),
      Gap(14),
      Text(context.i18n.onboardingPermissionDeniedTitle).h4,
      Gap(8),
      Text(context.i18n.onboardingPermissionDeniedBody).small.muted,
      Gap(18),
      Row(mainAxisAlignment: MainAxisAlignment.end, children: [
        GhostButton(onPressed: onContinueAnyway, child: Text(context.i18n.onboardingContinueAnyway)),
        Gap(10),
        PrimaryButton(onPressed: onAllow, child: Text(context.i18n.onboardingAllowBluetooth)),
      ]),
    ],
  );
}

Future<bool?> openPermissionDeniedSheet(BuildContext context) {
  return openSheet<bool>(
    context: context,
    position: OverlayPosition.bottom,
    builder: (sheetContext) => _sheetFrame(
      sheetContext,
      permissionDeniedSheetBody(
        sheetContext,
        onContinueAnyway: () => Navigator.of(sheetContext).pop(true),
        onAllow: () => Navigator.of(sheetContext).pop(false),
      ),
    ),
  );
}

/// Width-capped on desktop, like SramGuidedSheet (sram_setup_sheet.dart:81-88).
Widget _sheetFrame(BuildContext context, Widget child) {
  return Center(
    heightFactor: 1,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 520),
      child: Padding(padding: const EdgeInsets.all(20), child: child),
    ),
  );
}
```

If popping the sheet with a value via `Navigator.of(sheetContext).pop(true)` doesn't close shadcn sheets correctly, use the pattern `closeSheet(sheetContext)` + a captured local variable for the result — check how existing code returns values from sheets (`openSheet<T>` is generic, so `pop(value)` should work; verify with one manual run).

Wire in `onboarding_page.dart`: `onHelp: () => openOnboardingHelpSheet(context, _step)`.

- [ ] **Step 2: ARB strings** (design copy, condensed to the channels we actually have)

```json
  "onboardingHelpSheetTitle": "Need a hand?",
  "onboardingHelpSheetIntro": "Setup should take a couple of minutes. If something's stuck, start here.",
  "onboardingHelpAppTitle": "Which app should I pick?",
  "onboardingHelpAppBody": "Pick the app you actually ride in. Official integrations are tested with BikeControl; the others connect through generic methods.",
  "onboardingHelpWhereTitle": "Same device or another?",
  "onboardingHelpWhereBody": "If your trainer app is on an Apple TV, PC or tablet and BikeControl is elsewhere, choose 'On another device'.",
  "onboardingHelpControllerTitle": "My controller isn't showing up",
  "onboardingHelpControllerBody": "Wake it with a button press, close any app already holding it (Zwift especially), and keep it within a couple of metres.",
  "onboardingHelpVsTitle": "Do I need a smart trainer?",
  "onboardingHelpVsBody": "No — this step is optional. Connect one only if you want BikeControl to compute your gears and resistance.",
  "onboardingHelpConnectionTitle": "It won't connect",
  "onboardingHelpConnectionBody": "Check both devices are on the same Wi-Fi for Network, or enable Local as a fallback on macOS, Windows and Android.",
  "onboardingHelpDoneTitle": "What are the test-mode limits?",
  "onboardingHelpDoneBody": "A daily command budget, plus limited virtual shifting per day. Enough to verify your setup works.",
  "onboardingHelpGuides": "Setup guides",
  "onboardingHelpTroubleshooting": "Troubleshooting",
  "onboardingHelpSupport": "Contact support",
  "onboardingHelpBackToSetup": "Back to setup",
  "onboardingPermissionDeniedTitle": "BikeControl can't find devices",
  "onboardingPermissionDeniedBody": "Without Bluetooth permission there's no way to reach your controller. You can still finish setup and grant it later in Settings.",
  "onboardingContinueAnyway": "Continue anyway",
  "onboardingAllowBluetooth": "Allow Bluetooth",
```

Run: `flutter pub global run intl_utils:generate`

- [ ] **Step 3: Snapshot both sheet bodies** (add to `test/onboarding_snapshot_test.dart`; render `onboardingHelpSheetBody(c, step: OnboardingStep.controller, onClose: () {})` and `permissionDeniedSheetBody(c, onContinueAnyway: () {}, onAllow: () {})` inside a `Card` at width 380). Run and view the PNGs.

- [ ] **Step 4: Verify + commit**

`flutter analyze` clean; `flutter test test/onboarding_snapshot_test.dart` passes.

```bash
git add lib/pages/onboarding lib/i10n/intl_en.arb lib/gen test/onboarding_snapshot_test.dart
git commit -m "feat(onboarding): per-step help sheet and permission-denied sheet"
```

---

### Task 4: Refactor — extract app/target selection side-effects (behavior-preserving)

**Files:**
- Create: `lib/utils/trainer_setup.dart`
- Modify: `lib/pages/configuration.dart` (`TrainerAppSelect.onChanged` at ~281-322; `_setTarget` at ~147-165)

**Interfaces:**
- Consumes: everything the two existing blocks already use (`core.whooshLink`, emulators, `core.settings.setTrainerApp`, `core.actionHandler`, `core.logic.startEnabledConnectionMethod`, `core.settings.setLastTarget`, `core.settings.setObpMdnsEnabled`, `core.settings.setLocalEnabled`).
- Produces:
  - `Future<void> applyTrainerAppSelection(SupportedApp selectedApp)` — the EXACT body currently in `TrainerAppSelect.onChanged` (configuration.dart:281-322), moved verbatim (it uses no `BuildContext`).
  - `Future<void> applyTargetSelection(Target target)` — the EXACT body of `_setTarget` (configuration.dart:147-165) minus the unused `BuildContext` parameter.

- [ ] **Step 1: Create `lib/utils/trainer_setup.dart`** and move both bodies verbatim (imports: `core.dart`, `supported_app.dart`, the app classes used in the `is` checks (`MyWhoosh`, `CustomApp`, `BikeControl`), `multi.dart` for `Target`, `flutter/foundation.dart` + `dart:io` for the `kIsWeb`/`Platform.isWindows` check). Add doc comments stating these are shared by `ConfigurationPage` and the onboarding wizard.

- [ ] **Step 2: Replace the originals with delegation**

`TrainerAppSelect.onChanged` becomes:

```dart
      onChanged: (selectedApp) async {
        await applyTrainerAppSelection(selectedApp!);
        onUpdate();
      },
```

`_setTarget` becomes:

```dart
  Future<void> _setTarget(BuildContext context, Target target) async {
    await applyTargetSelection(target);
  }
```

(Keep `_setTarget`'s signature so call sites don't change; or inline `applyTargetSelection` at the two call sites and delete `_setTarget` — either is fine, prefer the smaller diff.)

- [ ] **Step 3: Verify no behavior change**

Run: `flutter analyze lib/utils/trainer_setup.dart lib/pages/configuration.dart` → clean.
Diff check: the moved bodies must be character-identical to the originals apart from `selectedApp!` null-handling (the original used `selectedApp!` mid-body — make the parameter non-nullable and drop the `!`).

- [ ] **Step 4: Commit**

```bash
git add lib/utils/trainer_setup.dart lib/pages/configuration.dart
git commit -m "refactor: extract trainer app/target selection side-effects for reuse"
```

---

### Task 5: Step 1 — trainer app grid

**Files:**
- Create: `lib/pages/onboarding/steps/step_app.dart`
- Modify: `lib/pages/onboarding/onboarding_page.dart`
- Modify: `lib/i10n/intl_en.arb`
- Test: extend `test/onboarding_snapshot_test.dart`

**Interfaces:**
- Consumes: `SupportedApp.supportedApps` (supported_app.dart:106), `app.officialIntegration`, `app.logoAsset`, `app.name`; `SelectableCard` (`lib/pages/button_edit.dart:1486` — params `title`, `subtitle`, `isActive`, `onPressed`); existing ARB keys `officiallySupported` and `otherTrainerApps` for the group headers; `applyTrainerAppSelection` (Task 4).
- Produces: `Widget onboardingAppBody(BuildContext context, {required SupportedApp? selected, required ValueChanged<SupportedApp> onSelect})`.

- [ ] **Step 1: Implement the body**

```dart
// lib/pages/onboarding/steps/step_app.dart
import 'package:bike_control/pages/button_edit.dart' show SelectableCard;
import 'package:bike_control/utils/i18n_extension.dart';
import 'package:bike_control/utils/keymap/apps/supported_app.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

Widget onboardingAppBody(BuildContext context,
    {required SupportedApp? selected, required ValueChanged<SupportedApp> onSelect}) {
  final official = SupportedApp.supportedApps.where((a) => a.officialIntegration).toList();
  final other = SupportedApp.supportedApps.where((a) => !a.officialIntegration).toList();

  Widget grid(List<SupportedApp> apps) => LayoutBuilder(builder: (context, constraints) {
        final cols = constraints.maxWidth >= 560 ? 5 : 3;
        return GridView.count(
          crossAxisCount: cols,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          childAspectRatio: 1.1,
          children: [
            for (final app in apps)
              SelectableCard(
                isActive: selected?.name == app.name,
                title: Center(
                  child: app.logoAsset != null
                      ? Image.asset(app.logoAsset!, height: 36, fit: BoxFit.contain)
                      : Container(
                          width: 36,
                          height: 36,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(10),
                            color: Theme.of(context).colorScheme.muted,
                          ),
                          child: Text(app.name.characters.first.toUpperCase()).semibold.muted,
                        ),
                ),
                subtitle: Center(child: Text(app.name, textAlign: TextAlign.center).xSmall.semibold),
                onPressed: () => onSelect(app),
              ),
          ],
        );
      });

  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(context.i18n.onboardingAppTitle).h4,
      Gap(6),
      Text(context.i18n.onboardingAppSubtitle).small.muted,
      Gap(18),
      Text(context.i18n.officiallySupported).xSmall.semibold.muted,
      Gap(8),
      grid(official),
      Gap(18),
      Text(context.i18n.otherTrainerApps).xSmall.semibold.muted,
      Gap(8),
      grid(other),
      Gap(14),
      Text(context.i18n.onboardingAppNote).xSmall.muted,
    ],
  );
}
```

(Check `SelectableCard`'s exact fields against `button_edit.dart:1486-1506` before use; if its `title`/`subtitle` layout fights the tile design, build the tile inside `title:` only. If `characters` needs an import, it's `package:characters/characters.dart` — but shadcn's barrel usually re-exports it; fall back to `app.name.substring(0, 1)`.)

- [ ] **Step 2: Wire into the page**

In `_OnboardingPageState`, add `SupportedApp? _selectedApp;` initialized in `initState` from `core.settings.getTrainerApp()`. The step body switch (start of the pattern used by all later tasks):

```dart
  Widget _body(BuildContext context) => switch (_step) {
        OnboardingStep.app => onboardingAppBody(
            context,
            selected: _selectedApp,
            onSelect: (a) => setState(() => _selectedApp = a),
          ),
        _ => const SizedBox(),
      };

  List<Widget> _footer(BuildContext context) => switch (_step) {
        OnboardingStep.app => [
            PrimaryButton(
              onPressed: _selectedApp == null
                  ? null
                  : () async {
                      await applyTrainerAppSelection(_selectedApp!);
                      _next();
                    },
              child: Text(_selectedApp == null
                  ? context.i18n.onboardingAppPickToContinue
                  : context.i18n.onboardingAppContinueWith(_selectedApp!.name)),
            ),
          ],
        _ => [PrimaryButton(onPressed: _next, child: Text(context.i18n.onboardingContinue))],
      };
```

- [ ] **Step 3: ARB** (design copy)

```json
  "onboardingAppTitle": "Which app do you ride with?",
  "onboardingAppSubtitle": "We'll pre-select the right connection method and button mapping for it.",
  "onboardingAppNote": "Official apps are tested with BikeControl and get verified button mappings. The others work through generic connection methods.",
  "onboardingAppPickToContinue": "Pick an app to continue",
  "onboardingAppContinueWith": "Continue with {app}",
  "@onboardingAppContinueWith": {"placeholders": {"app": {"type": "String"}}},
```

Run: `flutter pub global run intl_utils:generate`

- [ ] **Step 4: Snapshot** — add `onboarding_step_app` (selected = null) and `onboarding_step_app_selected` (selected = `SupportedApp.supportedApps.first`) at width 380 and one at width 640 (5 columns). Run, view PNGs.

- [ ] **Step 5: Commit**

```bash
git add lib/pages/onboarding lib/i10n/intl_en.arb lib/gen test/onboarding_snapshot_test.dart
git commit -m "feat(onboarding): step 1 trainer app picker grid"
```

---

### Task 6: Step 2 — where does the app run

**Files:**
- Create: `lib/pages/onboarding/steps/step_where.dart`
- Modify: `lib/pages/onboarding/onboarding_page.dart`
- Modify: `lib/i10n/intl_en.arb`
- Test: extend `test/onboarding_snapshot_test.dart`

**Interfaces:**
- Consumes: `Target` enum (`lib/utils/requirements/multi.dart:133` — `.icon`, `.getTitle(context)`, `.getDescription(app)`), `SelectableCard`, `applyTargetSelection` (Task 4).
- Produces: `Widget onboardingWhereBody(BuildContext context, {required SupportedApp app, required Target? selected, required ValueChanged<Target> onSelect})`.

- [ ] **Step 1: Implement**

```dart
// lib/pages/onboarding/steps/step_where.dart
import 'package:bike_control/pages/button_edit.dart' show SelectableCard;
import 'package:bike_control/utils/i18n_extension.dart';
import 'package:bike_control/utils/keymap/apps/supported_app.dart';
import 'package:bike_control/utils/requirements/multi.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

Widget onboardingWhereBody(BuildContext context,
    {required SupportedApp app, required Target? selected, required ValueChanged<Target> onSelect}) {
  String enables(Target t) => t == Target.thisDevice
      ? context.i18n.onboardingWhereEnablesLocal
      : context.i18n.onboardingWhereEnablesNetwork;
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(context.i18n.onboardingWhereTitle(app.name)).h4,
      Gap(6),
      Text(context.i18n.onboardingWhereSubtitle).small.muted,
      Gap(18),
      for (final target in [Target.thisDevice, Target.otherDevice]) ...[
        SelectableCard(
          isActive: selected == target,
          title: Row(children: [
            Icon(target.icon, size: 22),
            Gap(12),
            Expanded(child: Text(target.getTitle(context)).semibold),
          ]),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Gap(4),
              Text(target.getDescription(app)).xSmall.muted,
              Gap(8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  color: selected == target
                      ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.09)
                      : Theme.of(context).colorScheme.muted,
                ),
                child: Text(enables(target)).xSmall,
              ),
            ],
          ),
          onPressed: () => onSelect(target),
        ),
        Gap(10),
      ],
      Gap(4),
      Text(context.i18n.onboardingWhereChangeLater).xSmall.muted,
    ],
  );
}
```

- [ ] **Step 2: Wire** — add `Target? _selectedTarget;` (init from `core.settings.getLastTarget()`). Body case returns `onboardingWhereBody(context, app: _selectedApp!, selected: _selectedTarget, onSelect: (t) => setState(() => _selectedTarget = t))`. Footer case: `PrimaryButton` disabled while `_selectedTarget == null`, else `await applyTargetSelection(_selectedTarget!); _next();`. (`_selectedApp` is non-null on this step — it's only reachable after step 1's footer.)

- [ ] **Step 3: ARB** (design copy)

```json
  "onboardingWhereTitle": "Where does {app} run?",
  "@onboardingWhereTitle": {"placeholders": {"app": {"type": "String"}}},
  "onboardingWhereSubtitle": "This decides how BikeControl talks to it.",
  "onboardingWhereEnablesLocal": "Enables the Local method — key presses and taps go straight to the app.",
  "onboardingWhereEnablesNetwork": "Enables the Network method — BikeControl finds the app over your Wi-Fi.",
  "onboardingWhereChangeLater": "You can change this later in Connection Settings.",
```

Run: `flutter pub global run intl_utils:generate`

- [ ] **Step 4: Snapshot** `onboarding_step_where` (none selected) + `…_selected` (`Target.otherDevice`), width 380. Run, view.

- [ ] **Step 5: Commit** — `git add …; git commit -m "feat(onboarding): step 2 where-does-the-app-run cards"`

---

### Task 7: Refactor — extract connection-method tile lists from TrainerPage

**Files:**
- Create: `lib/widgets/apps/connection_tiles.dart`
- Modify: `lib/pages/trainer.dart:57-98`

**Interfaces:**
- Consumes: the exact tile widgets + `core.logic.show*` predicates currently inlined in `trainer.dart:57-98`.
- Produces: `({List<Widget> recommended, List<Widget> other}) buildConnectionMethodTiles({required bool small, required VoidCallback onUpdate})` — the moved code verbatim, with `small:` passed through to every tile and `onUpdate` used where the original used its local callbacks (`ZwiftMdnsTile`/`ZwiftTile`).

- [ ] **Step 1: Move `trainer.dart:57-98` verbatim** into the new function (both lists, including the `showLocalAsOther` / `showWhooshLinkAsOther` locals). Replace the inlined code in `TrainerPage.build` with:

```dart
    final tiles = buildConnectionMethodTiles(small: false, onUpdate: () => setState(() {}));
    final recommendedTiles = tiles.recommended;
    final otherTiles = tiles.other;
```

(Match whatever the original `onUpdate` closures did — read the current `ZwiftMdnsTile(onUpdate: …)` bodies in trainer.dart and preserve them via the `onUpdate` parameter.)

- [ ] **Step 2: Verify** — `flutter analyze lib/widgets/apps/connection_tiles.dart lib/pages/trainer.dart` clean. Launch check deferred to Task 13's manual QA.

- [ ] **Step 3: Commit** — `git commit -m "refactor: extract connection-method tile lists for reuse by onboarding"`

---

### Task 8: Step 3a — controller: permission, scanning, list, empty

**Files:**
- Create: `lib/pages/onboarding/steps/step_controller.dart`
- Modify: `lib/pages/onboarding/onboarding_page.dart`
- Modify: `lib/i10n/intl_en.arb`
- Test: extend `test/onboarding_snapshot_test.dart`

**Interfaces:**
- Consumes: `core.permissions.getScanRequirements()` → `Future<List<PlatformRequirement>>` (empty = granted; `lib/utils/core.dart:126`), `openPermissionSheet(context, notDone)` (`lib/widgets/ui/connection_method.dart:329`), `core.connection.performScanning()`, `core.connection.isScanning` (`ValueNotifier<bool>`), `core.connection.controllerDevices` (`List<BaseDevice>`), `core.connection.connectionStream` (`Stream<BaseDevice>`), `SmoothWifiAnimation({size = 140, label = 'SCANNING'})`, `openPermissionDeniedSheet` (Task 3), `ControllerPhase` (Task 2), `device.icon`, `device.name`, `device.isConnected`.
- Produces: `Widget onboardingControllerBody(BuildContext context, {required ControllerPhase phase, required List<BaseDevice> devices, required String appName})` — devices only rendered in `list` phase; connected styling derived from `device.isConnected`.

- [ ] **Step 1: Implement the body**

```dart
// lib/pages/onboarding/steps/step_controller.dart
import 'package:bike_control/bluetooth/devices/base_device.dart';
import 'package:bike_control/pages/onboarding/onboarding_models.dart';
import 'package:bike_control/utils/i18n_extension.dart';
import 'package:bike_control/widgets/guided_operation_sheet.dart';
import 'package:bike_control/widgets/ui/wifi_animation.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

Widget _infoRow(BuildContext context, IconData icon, String title, String sub) {
  return Container(
    margin: const EdgeInsets.only(bottom: 8),
    padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.muted,
      borderRadius: BorderRadius.circular(10),
    ),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(icon, size: 18),
      Gap(12),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title).small.semibold,
          Text(sub).xSmall.muted,
        ]),
      ),
    ]),
  );
}

Widget onboardingDeviceRow(BuildContext context, BaseDevice device) {
  final connected = device.isConnected;
  final scheme = Theme.of(context).colorScheme;
  return Container(
    margin: const EdgeInsets.only(bottom: 8),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      border: Border.all(color: connected ? const Color(0xFF22C55E) : scheme.border, width: 1.5),
      borderRadius: BorderRadius.circular(12),
      color: scheme.card,
    ),
    child: Row(children: [
      Icon(connected ? LucideIcons.check : device.icon, size: 20,
          color: connected ? const Color(0xFF22C55E) : null),
      Gap(12),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(device.name).small.semibold,
          Text(connected ? context.i18n.onboardingDeviceConnected : context.i18n.onboardingDeviceConnecting).xSmall.muted,
        ]),
      ),
      if (connected) SecondaryBadge(child: Text(context.i18n.onboardingDeviceConnected)),
    ]),
  );
}

Widget onboardingControllerBody(BuildContext context,
    {required ControllerPhase phase, required List<BaseDevice> devices, required String appName}) {
  final reduceMotion = MediaQuery.of(context).disableAnimations;
  final scheme = Theme.of(context).colorScheme;
  final anyConnected = devices.any((d) => d.isConnected);

  switch (phase) {
    case ControllerPhase.permission:
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(context.i18n.onboardingBluetoothTitle).h4,
        Gap(6),
        Text(context.i18n.onboardingBluetoothSubtitle).small.muted,
        Gap(16),
        Center(child: StageBadge(icon: LucideIcons.bluetooth, tone: scheme.primary,
            wash: scheme.primary.withValues(alpha: 0.1), reduceMotion: reduceMotion)),
        Gap(20),
        _infoRow(context, LucideIcons.radar, context.i18n.onboardingBluetoothFindTitle, context.i18n.onboardingBluetoothFindSub),
        _infoRow(context, LucideIcons.bell, context.i18n.onboardingBluetoothNotifyTitle, context.i18n.onboardingBluetoothNotifySub),
        Gap(6),
        _infoRow(context, LucideIcons.shieldCheck, context.i18n.onboardingBluetoothPrivacy, ''),
      ]);
    case ControllerPhase.scanning:
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(context.i18n.onboardingScanTitle).h4,
        Gap(6),
        Text(context.i18n.onboardingScanSubtitle).small.muted,
        Gap(24),
        Center(child: SmoothWifiAnimation()),
        Gap(20),
        Center(child: Text(context.i18n.scanningForDevices).small.muted),
      ]);
    case ControllerPhase.empty:
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(context.i18n.onboardingScanEmptyTitle).h4,
        Gap(6),
        Text(context.i18n.onboardingScanEmptySubtitle).small.muted,
        Gap(18),
        _infoRow(context, LucideIcons.power, context.i18n.onboardingScanEmptyWakeTitle, context.i18n.onboardingScanEmptyWakeSub),
        _infoRow(context, LucideIcons.unlink, context.i18n.onboardingScanEmptyDisconnectTitle, context.i18n.onboardingScanEmptyDisconnectSub),
        _infoRow(context, LucideIcons.ruler, context.i18n.onboardingScanEmptyCloserTitle, context.i18n.onboardingScanEmptyCloserSub),
      ]);
    case ControllerPhase.list:
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(anyConnected
                ? context.i18n.onboardingControllerReadyTitle
                : context.i18n.onboardingControllerListTitle)
            .h4,
        Gap(6),
        Text(anyConnected
                ? context.i18n.onboardingControllerReadySubtitle
                : context.i18n.onboardingControllerListSubtitle)
            .small
            .muted,
        Gap(16),
        for (final d in devices) onboardingDeviceRow(context, d),
        Gap(10),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          SizedBox(width: 14, height: 14, child: CircularProgressIndicator()),
          Gap(8),
          Text(context.i18n.onboardingStillScanning).xSmall.muted,
        ]),
        if (anyConnected) ...[
          Gap(12),
          _infoRow(context, LucideIcons.lightbulb, context.i18n.onboardingControllerMapped(appName), ''),
        ],
      ]);
  }
}
```

(`CircularProgressIndicator` is shadcn's — it takes `size:` in this codebase (`CircularProgressIndicator(size:)` per repo usage); adjust to `CircularProgressIndicator(size: 14)` if the SizedBox wrapper misbehaves. `SecondaryBadge` exists — used at `connection_method.dart:221`.)

- [ ] **Step 2: Page wiring — phase transitions**

In `_OnboardingPageState`:

```dart
  ControllerPhase _controllerPhase = ControllerPhase.permission;
  Timer? _emptyScanTimer;
  StreamSubscription<BaseDevice>? _connectionSub;

  @override
  void initState() {
    super.initState();
    _selectedApp = core.settings.getTrainerApp();
    _selectedTarget = core.settings.getLastTarget();
    _connectionSub = core.connection.connectionStream.listen((_) {
      if (!mounted) return;
      setState(() {
        if (_step == OnboardingStep.controller &&
            (_controllerPhase == ControllerPhase.scanning || _controllerPhase == ControllerPhase.empty) &&
            core.connection.controllerDevices.isNotEmpty) {
          _controllerPhase = ControllerPhase.list;
          _emptyScanTimer?.cancel();
        }
      });
    });
  }

  @override
  void dispose() {
    _connectionSub?.cancel();
    _emptyScanTimer?.cancel();
    super.dispose();
  }

  Future<void> _enterControllerStep() async {
    try {
      final requirements = await core.permissions.getScanRequirements();
      if (!mounted) return;
      if (requirements.isEmpty) {
        _startScanPhase();
      } else {
        setState(() => _controllerPhase = ControllerPhase.permission);
      }
    } catch (e, s) {
      recordError(e, s, context: 'onboarding controller step requirements');
    }
  }

  void _startScanPhase() {
    setState(() => _controllerPhase =
        core.connection.controllerDevices.isNotEmpty ? ControllerPhase.list : ControllerPhase.scanning);
    core.connection.performScanning();
    _emptyScanTimer?.cancel();
    _emptyScanTimer = Timer(const Duration(seconds: 15), () {
      if (!mounted) return;
      if (_controllerPhase == ControllerPhase.scanning && core.connection.controllerDevices.isEmpty) {
        setState(() => _controllerPhase = ControllerPhase.empty);
      }
    });
  }

  Future<void> _onAllowBluetooth() async {
    final requirements = await core.permissions.getScanRequirements();
    if (!mounted) return;
    if (requirements.isEmpty) {
      _startScanPhase();
      return;
    }
    await openPermissionSheet(context, requirements);
    if (!mounted) return;
    final recheck = await core.permissions.getScanRequirements();
    if (!mounted) return;
    if (recheck.isEmpty) _startScanPhase();
  }

  Future<void> _onPermissionNotNow() async {
    final continueAnyway = await openPermissionDeniedSheet(context);
    if (!mounted) return;
    if (continueAnyway == true) {
      _next();
    } else if (continueAnyway == false) {
      await _onAllowBluetooth();
    }
  }
```

Call `_enterControllerStep()` whenever `_next()`/`_back()` lands on `OnboardingStep.controller` (add a post-transition hook inside `_next`/`_back`). Body case: `onboardingControllerBody(context, phase: _controllerPhase, devices: core.connection.controllerDevices, appName: _selectedApp?.name ?? '')`. Footer cases:

- `permission`: `[PrimaryButton(onPressed: _onAllowBluetooth, child: Row([Icon(LucideIcons.bluetooth, size: 16), Gap(8), Text(context.i18n.onboardingAllowBluetooth)])), GhostButton(onPressed: _onPermissionNotNow, child: Text(context.i18n.onboardingNotNow))]`
- `scanning`: `[GhostButton(onPressed: () { _emptyScanTimer?.cancel(); setState(() => _controllerPhase = ControllerPhase.empty); }, child: Text(context.i18n.onboardingCantFindController))]`
- `empty`: `[PrimaryButton(onPressed: _startScanPhase, child: Text(context.i18n.onboardingScanAgain)), GhostButton(onPressed: _next, child: Text(context.i18n.onboardingSetUpLater))]`
- `list`: Task 9 replaces this; for now `[GhostButton(onPressed: _next, child: Text(context.i18n.onboardingContinue))]`.

- [ ] **Step 3: ARB** (design copy)

```json
  "onboardingBluetoothTitle": "Allow Bluetooth for BikeControl",
  "onboardingBluetoothSubtitle": "BikeControl needs to search for nearby devices and tell you when the connection changes.",
  "onboardingBluetoothFindTitle": "Find nearby controllers",
  "onboardingBluetoothFindSub": "Scan for your shifter or click device.",
  "onboardingBluetoothNotifyTitle": "Keep you posted",
  "onboardingBluetoothNotifySub": "Tell you when a device connects or drops out.",
  "onboardingBluetoothPrivacy": "BikeControl never uses this for location or tracking.",
  "onboardingNotNow": "Not now",
  "onboardingScanTitle": "Looking for your controller",
  "onboardingScanSubtitle": "Make sure it's powered on, in range, and not connected to another app.",
  "onboardingScanEmptyTitle": "No controllers found",
  "onboardingScanEmptySubtitle": "Nothing answered the scan. A few things usually fix it:",
  "onboardingScanEmptyWakeTitle": "Wake the device",
  "onboardingScanEmptyWakeSub": "Press a button or paddle to wake it up.",
  "onboardingScanEmptyDisconnectTitle": "Disconnect it elsewhere",
  "onboardingScanEmptyDisconnectSub": "Close Zwift or any app that already holds the connection.",
  "onboardingScanEmptyCloserTitle": "Get closer",
  "onboardingScanEmptyCloserSub": "Keep it within a couple of metres while pairing.",
  "onboardingScanAgain": "Scan again",
  "onboardingSetUpLater": "Set this up later",
  "onboardingCantFindController": "Can't find your controller?",
  "onboardingControllerListTitle": "Controllers",
  "onboardingControllerListSubtitle": "Devices connect automatically as they're found.",
  "onboardingControllerReadyTitle": "Your controller is ready",
  "onboardingControllerReadySubtitle": "Give it a try — press a button and watch BikeControl react.",
  "onboardingStillScanning": "Still scanning…",
  "onboardingDeviceConnected": "Connected",
  "onboardingDeviceConnecting": "Connecting…",
  "onboardingControllerMapped": "Your buttons are mapped for {app} already. You can fine-tune every one later.",
  "@onboardingControllerMapped": {"placeholders": {"app": {"type": "String"}}},
```

Run: `flutter pub global run intl_utils:generate`

- [ ] **Step 4: Snapshot** all four phases at width 380 (`permission`, `scanning` with `settle: false` — the wifi animation loops, `empty`, `list` with a fake device: construct e.g. `SramAxs(BleDevice(deviceId: 'snap', name: 'SRAM Rival AXS'))` like `sram_states_snapshot_test.dart:26` and flip `isConnected = true` on one). Run, view PNGs.

- [ ] **Step 5: Commit** — `git commit -m "feat(onboarding): step 3 controller permission/scan/list/empty phases"`

---

### Task 9: Step 3b — device sub-flows + press-a-button-to-continue

**Files:**
- Create: `lib/pages/onboarding/widgets/onboarding_button_hint.dart`
- Modify: `lib/bluetooth/devices/sram/sram_axs.dart` (public guided-setup entry)
- Modify: `lib/pages/onboarding/onboarding_page.dart`
- Modify: `lib/i10n/intl_en.arb`
- Test: extend `test/onboarding_snapshot_test.dart`

**Interfaces:**
- Consumes: `core.connection.actionStream` (`Stream<BaseNotification>`; filter `ButtonNotification` — `lib/bluetooth/messages/notification.dart:37`, fields `device`, `buttonsClicked`), `UnlockPage({required ZwiftClickV2 device})` opened via `openDrawer(context:, position: OverlayPosition.bottom, builder: (_) => UnlockPage(device: d))` (pattern: zwift_clickv2.dart:293-297), `_runGuidedOperation` params at `sram_axs.dart:359-369`, `core.settings.getSramShiftingDisabled(String serial)` (settings.dart:619).
- Produces:
  - On `SramAxs`: `Future<void> showGuidedSetup(BuildContext context)` (public wrapper around the existing private `_runGuidedOperation` call with the exact args from sram_axs.dart:359-369) and `bool get needsGuidedSetup`.
  - `class OnboardingButtonHint extends StatelessWidget { const OnboardingButtonHint({super.key, required this.onContinue}); final VoidCallback onContinue; }`

- [ ] **Step 1: SramAxs public entry**

In `sram_axs.dart`, next to the existing setup button handler:

```dart
  /// Whether the guided "disable on-device shifting" setup hasn't run yet for
  /// this derailleur. Uses the same serial key as the setup itself.
  bool get needsGuidedSetup => !core.settings.getSramShiftingDisabled(_serialKey);

  /// Opens the same guided setup sheet as the device card's
  /// "Set up SRAM control" button. Used by the onboarding wizard.
  Future<void> showGuidedSetup(BuildContext context) {
    final l = AppLocalizations.of(context);
    return _runGuidedOperation(
      context,
      title: l.sramSetup,
      intro: l.sramSetupIntro,
      successMessage: l.sramSetupSuccess,
      confirmIcon: LucideIcons.slidersHorizontal,
      runningTitle: l.sramSettingUp,
      successTitle: l.sramAllSet,
      checklistItems: [l.sramChecklistPairing, l.sramChecklistBackingUp, l.sramChecklistDisabling],
      operation: setupControl,
    );
  }
```

(Verify `_serialKey` is the settings key used by the existing setup path — grep `getSramShiftingDisabled`/`setSramShiftingDisabled` call sites inside `sram_axs.dart` and use the same expression.)

- [ ] **Step 2: Button hint widget**

```dart
// lib/pages/onboarding/widgets/onboarding_button_hint.dart
import 'package:bike_control/utils/i18n_extension.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

/// "Press a button on your controller to continue … or tap here".
/// The actual advance-on-hardware-press lives in the page's actionStream
/// listener; this widget is the visual + tap fallback.
class OnboardingButtonHint extends StatefulWidget {
  const OnboardingButtonHint({super.key, required this.onContinue});
  final VoidCallback onContinue;

  @override
  State<OnboardingButtonHint> createState() => _OnboardingButtonHintState();
}

class _OnboardingButtonHintState extends State<OnboardingButtonHint> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1600));

  @override
  void initState() {
    super.initState();
    if (!MediaQueryData.fromView(View.of(context)).disableAnimations) {
      _pulse.repeat();
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Button.ghost(
      onPressed: widget.onContinue,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          border: Border.all(color: scheme.primary, width: 1.5),
          borderRadius: BorderRadius.circular(12),
          color: scheme.primary.withValues(alpha: 0.08),
        ),
        child: Row(children: [
          AnimatedBuilder(
            animation: _pulse,
            builder: (context, child) => Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: scheme.primary,
                boxShadow: [
                  BoxShadow(
                    color: scheme.primary.withValues(alpha: (1 - _pulse.value) * 0.45),
                    spreadRadius: _pulse.value * 10,
                  ),
                ],
              ),
              child: Icon(LucideIcons.chevronUp, size: 17, color: const Color(0xFFFFFFFF)),
            ),
          ),
          Gap(12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(context.i18n.onboardingPressButtonToContinue).small.semibold,
              Text(context.i18n.onboardingOrTapHere).xSmall.muted,
            ]),
          ),
        ]),
      ),
    );
  }
}
```

(If `MediaQueryData.fromView(View.of(context))` in `initState` is awkward, gate `_pulse.repeat()` in `didChangeDependencies` using `MediaQuery.of(context).disableAnimations` — that's the cleaner Flutter idiom.)

- [ ] **Step 3: Page wiring**

Add to `_OnboardingPageState`:

```dart
  final Set<String> _setupPrompted = {};
  StreamSubscription<BaseNotification>? _actionSub;
```

In `initState`, subscribe:

```dart
    _actionSub = core.connection.actionStream.listen((notification) {
      if (!mounted || _step != OnboardingStep.controller) return;
      if (notification is ButtonNotification &&
          notification.buttonsClicked.isNotEmpty &&
          notification.device.isConnected) {
        _next();
      }
    });
```

Cancel in `dispose`. In the `connectionStream` listener (Task 8), after the phase update, auto-open sub-flows for devices that just connected and need setup:

```dart
      for (final d in core.connection.controllerDevices) {
        if (!d.isConnected || _setupPrompted.contains(d.uniqueId)) continue;
        if (_step != OnboardingStep.controller) continue;
        if (d is ZwiftClickV2 && !d.isUnlocked.value && !d.alreadyUnlocked.value) {
          _setupPrompted.add(d.uniqueId);
          openDrawer(context: context, position: OverlayPosition.bottom, builder: (_) => UnlockPage(device: d));
        } else if (d is SramAxs && d.needsGuidedSetup) {
          _setupPrompted.add(d.uniqueId);
          unawaited(d.showGuidedSetup(context));
        }
      }
```

(`ZwiftClickV2` check must come before any `ZwiftRide` handling since `ZwiftClickV2 extends ZwiftRide`. `ZwiftClickV2LeftSide`/`RightSide` are subclasses of `ZwiftClickV2` — the `is` check covers them; guard against opening the drawer twice for the pair by keying `_setupPrompted` on `uniqueId`.)

Footer for `list` phase replaces Task 8's placeholder:

```dart
        ControllerPhase.list => [
            if (core.connection.controllerDevices.any((d) => d.isConnected))
              OnboardingButtonHint(onContinue: _next)
            else
              GhostButton(
                onPressed: () {
                  _emptyScanTimer?.cancel();
                  setState(() => _controllerPhase = ControllerPhase.empty);
                },
                child: Text(context.i18n.onboardingCantFindController),
              ),
          ],
```

- [ ] **Step 4: ARB**

```json
  "onboardingPressButtonToContinue": "Press a button on your controller to continue",
  "onboardingOrTapHere": "…or tap here",
```

Run: `flutter pub global run intl_utils:generate`

- [ ] **Step 5: Snapshot** the hint (`OnboardingButtonHint(onContinue: () {})`, width 380, `settle: false`). Run `flutter test test/onboarding_snapshot_test.dart` + `flutter analyze` → clean.

- [ ] **Step 6: Commit** — `git commit -m "feat(onboarding): device sub-flows and press-a-button-to-continue"`

---

### Task 10: Step 4 — virtual shifting (optional)

**Files:**
- Create: `lib/pages/onboarding/steps/step_trainer.dart`
- Modify: `lib/pages/onboarding/onboarding_page.dart`
- Modify: `lib/i10n/intl_en.arb`
- Test: extend `test/onboarding_snapshot_test.dart`

**Interfaces:**
- Consumes: `core.connection.proxyDevices` (`List<ProxyDevice>`), `ProxyDevice.isSmartTrainer`, `.isStarting`, `.isStartedListenable`, `.isConnectedListenable`, `.trainerKey`, `.defaultRetrofitMode`, `.setRetrofitMode`, `.startProxy()`; the tap sequence from `lib/pages/proxy.dart:57-84` (trial gate via `IAPManager.instance.isTrialExpired` + `showGoProDialog`, then `ProxyDeviceDetailsPage(device:)`); `launchUrlString`.
- Produces: `Widget onboardingTrainerBody(BuildContext context, {required SupportedApp app, required List<ProxyDevice> trainers, required void Function(ProxyDevice) onPick})` and `bool onboardingTrainerBridged(List<ProxyDevice> trainers)` (`=> trainers.any((t) => t.isStartedListenable.value || t.isConnectedListenable.value)`).

- [ ] **Step 1: Implement**

```dart
// lib/pages/onboarding/steps/step_trainer.dart
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
          Expanded(child: Text(t.name).small.semibold),
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
              Text(title).small.semibold,
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
    benefit(LucideIcons.slidersHorizontal, context.i18n.onboardingTrainerBenefitRatiosTitle, context.i18n.onboardingTrainerBenefitRatiosSub),
    benefit(LucideIcons.gauge, context.i18n.onboardingTrainerBenefitResistanceTitle, context.i18n.onboardingTrainerBenefitResistanceSub),
    benefit(LucideIcons.blocks, context.i18n.onboardingTrainerBenefitAppsTitle, context.i18n.onboardingTrainerBenefitAppsSub),
    Gap(14),
    Row(children: [
      Text(context.i18n.onboardingNearbyTrainers).xSmall.semibold.muted,
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
                Text(t.name).small.semibold,
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
```

(`lookingForSmartTrainers` is an existing key — proxy.dart uses it. Verify the exact key name with grep and reuse it.)

- [ ] **Step 2: Page wiring**

Body case: `onboardingTrainerBody(context, app: _selectedApp!, trainers: core.connection.proxyDevices, onPick: _onPickTrainer)`. Skip control: `onSkip: _step == OnboardingStep.virtualShifting && !onboardingTrainerBridged(core.connection.proxyDevices) ? _next : null` in the shell call. Footer:

```dart
        OnboardingStep.virtualShifting => [
            if (onboardingTrainerBridged(core.connection.proxyDevices))
              PrimaryButton(onPressed: _next, child: Text(context.i18n.onboardingContinue))
            else
              GhostButton(onPressed: _next, child: Text(context.i18n.onboardingLetAppHandleVs(_selectedApp!.name))),
          ],
```

`_onPickTrainer` mirrors `proxy.dart:57-84` exactly (trial gate, saved retrofit mode, `setAutoConnect`, `startProxy().catchError`, then `context.push(ProxyDeviceDetailsPage(device: device))`) — copy that block, adapting variable names; on return from the details page call `setState`. Also add per-proxy listeners so bridging updates the UI (pattern: `overview.dart:158-160` — `proxy.isStarting.addListener`, `proxy.isConnectedListenable.addListener`; add for current proxies in `initState` and for new ones in the `connectionStream` listener; remove in `dispose`).

- [ ] **Step 3: ARB** (design copy)

```json
  "onboardingTrainerTitle": "Let BikeControl handle Virtual Shifting",
  "onboardingTrainerSubtitle": "Connect your smart trainer and BikeControl computes every gear for you — in any app you ride.",
  "onboardingTrainerBenefitRatiosTitle": "Your gear ratios",
  "onboardingTrainerBenefitRatiosSub": "Set your own chainrings, cassette and gear count.",
  "onboardingTrainerBenefitResistanceTitle": "Consistent resistance",
  "onboardingTrainerBenefitResistanceSub": "Shifts feel the same in every app, every ride.",
  "onboardingTrainerBenefitAppsTitle": "Works where the app doesn't",
  "onboardingTrainerBenefitAppsSub": "Adds shifting to apps that have none.",
  "onboardingNearbyTrainers": "Nearby smart trainers",
  "onboardingTrainerMeta": "Supports virtual shifting",
  "onboardingTrainerHowItWorks": "How virtual shifting works",
  "onboardingTrainerConnectedTitle": "Trainer connected",
  "onboardingTrainerConnectedSubtitle": "BikeControl can now compute your gears and set the resistance.",
  "onboardingTrainerNextStepNote": "In the next step you'll point {app} at BikeControl's virtual trainer, so your gears come through.",
  "@onboardingTrainerNextStepNote": {"placeholders": {"app": {"type": "String"}}},
  "onboardingLetAppHandleVs": "Let {app} handle Virtual Shifting",
  "@onboardingLetAppHandleVs": {"placeholders": {"app": {"type": "String"}}},
```

Run: `flutter pub global run intl_utils:generate`

- [ ] **Step 4: Snapshot** intro (empty trainer list) at width 380. Run + view.

- [ ] **Step 5: Commit** — `git commit -m "feat(onboarding): step 4 virtual shifting with nearby trainers"`

---

### Task 11: Step 5 — connection methods + "Then in $app" + bridge card

**Files:**
- Create: `lib/pages/onboarding/steps/step_connection.dart`
- Create: `lib/pages/onboarding/onboarding_app_guides.dart`
- Modify: `lib/pages/onboarding/onboarding_page.dart`
- Modify: `lib/i10n/intl_en.arb`
- Test: extend `test/onboarding_snapshot_test.dart`

**Interfaces:**
- Consumes: `buildConnectionMethodTiles(small: true, onUpdate:)` (Task 7), existing ARB keys `recommendedConnectionMethods` / `otherConnectionMethods`, `Accordion`/`AccordionItem`/`AccordionTrigger` (pattern: trainer.dart:136), `core.logic.hasNoConnectionMethod` (core.dart roll-up — verify exact getter name by grep, alternatives: `!core.logic.emulatorEnabled && …`; use whatever `trainer_connection_settings.dart`'s PopScope gate uses at lines 43-53), `app.virtualGearAmount`.
- Produces:
  - `class OnboardingAppGuide { const OnboardingAppGuide({required this.steps, this.screenshotUrls = const [], this.guideUrl}); final List<String> steps; final List<String> screenshotUrls; final String? guideUrl; }`
  - `OnboardingAppGuide onboardingGuideFor(BuildContext context, SupportedApp app)`
  - `Widget onboardingConnectionBody(BuildContext context, {required SupportedApp app, required Target target, required bool hasTrainer, required String? trainerName, required VoidCallback onUpdate})`

- [ ] **Step 1: App guide data** (URLs from the design's per-app setup sources; steps as ARB strings)

```dart
// lib/pages/onboarding/onboarding_app_guides.dart
import 'package:bike_control/utils/i18n_extension.dart';
import 'package:bike_control/utils/keymap/apps/my_whoosh.dart';
import 'package:bike_control/utils/keymap/apps/rouvy.dart';
import 'package:bike_control/utils/keymap/apps/strappo.dart';
import 'package:bike_control/utils/keymap/apps/training_peaks.dart';
import 'package:bike_control/utils/keymap/apps/supported_app.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

class OnboardingAppGuide {
  const OnboardingAppGuide({required this.steps, this.screenshotUrls = const [], this.guideUrl});
  final List<String> steps;
  final List<String> screenshotUrls;
  final String? guideUrl;
}

const _shots = 'https://bikecontrol.app/images/';

OnboardingAppGuide onboardingGuideFor(BuildContext context, SupportedApp app) {
  final l = context.i18n;
  if (app is MyWhoosh) {
    return OnboardingAppGuide(
      steps: [l.onboardingGuideMyWhoosh1, l.onboardingGuideMyWhoosh2, l.onboardingGuideMyWhoosh3],
      screenshotUrls: const [
        '${_shots}mywhoosh_obc/4-mywhoosh-connection-screen.jpg',
        '${_shots}mywhoosh_obc/5-mywhoosh-openbikecontrol.jpg',
        '${_shots}mywhoosh_obc/6-bikecontrol-connected.jpg',
      ],
      guideUrl: 'https://bikecontrol.app/blog/mywhoosh-bikecontrol-partnership/',
    );
  }
  if (app is Rouvy) {
    return OnboardingAppGuide(
      steps: [l.onboardingGuideRouvy1, l.onboardingGuideRouvy2],
      screenshotUrls: const ['${_shots}blog_rouvy_screenshot.jpg'],
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
```

(Verify each app-class import path with a grep for `class Rouvy` / `class TrainingPeaks` / `class Strappo` — file names may differ.)

- [ ] **Step 2: Body**

```dart
// lib/pages/onboarding/steps/step_connection.dart
import 'package:bike_control/pages/onboarding/onboarding_app_guides.dart';
import 'package:bike_control/utils/i18n_extension.dart';
import 'package:bike_control/utils/keymap/apps/supported_app.dart';
import 'package:bike_control/utils/requirements/multi.dart';
import 'package:bike_control/widgets/apps/connection_tiles.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:url_launcher/url_launcher_string.dart';

Widget onboardingConnectionBody(BuildContext context,
    {required SupportedApp app,
    required Target target,
    required bool hasTrainer,
    required String? trainerName,
    required VoidCallback onUpdate}) {
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
    Text(context.i18n.recommendedConnectionMethods).xSmall.semibold.muted,
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
    Text(context.i18n.onboardingThenInApp(app.name)).xSmall.semibold.muted,
    Gap(8),
    Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(border: Border.all(color: scheme.border, width: 1.5), borderRadius: BorderRadius.circular(12)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (var i = 0; i < guide.steps.length; i++)
          Padding(
            padding: EdgeInsets.only(top: i == 0 ? 0 : 10),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                width: 22, height: 22, alignment: Alignment.center,
                decoration: BoxDecoration(shape: BoxShape.circle, color: scheme.primary),
                child: Text('${i + 1}').xSmall.semibold.withColor(const Color(0xFFFFFFFF)),
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
                    child: Image.network(url, height: 118,
                        errorBuilder: (_, __, ___) => const SizedBox.shrink()),
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
      Text(context.i18n.onboardingPairAsTrainer).xSmall.semibold.muted,
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
                  Text('${trainerName ?? ''} - BikeControl').small.semibold,
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
```

- [ ] **Step 3: Wire** — body case passes `app: _selectedApp!`, `target: _selectedTarget ?? Target.otherDevice`, `hasTrainer: onboardingTrainerBridged(core.connection.proxyDevices)`, `trainerName: core.connection.proxyDevices.where((t) => t.isStartedListenable.value || t.isConnectedListenable.value).firstOrNull?.name`, `onUpdate: () => setState(() {})`. Footer: `PrimaryButton` "Finish setup" → `_next()`; disable while no method is enabled — use the same predicate `TrainerConnectionSettingsPage`'s PopScope uses (`lib/pages/trainer_connection_settings.dart:43-53`); grep it and reuse.

- [ ] **Step 4: ARB** (design copy)

```json
  "onboardingConnectionTitle": "Connect to {app}",
  "@onboardingConnectionTitle": {"placeholders": {"app": {"type": "String"}}},
  "onboardingConnectionSubtitleLocal": "{app} runs on this device, so BikeControl can drive it directly.",
  "@onboardingConnectionSubtitleLocal": {"placeholders": {"app": {"type": "String"}}},
  "onboardingConnectionSubtitleNetwork": "BikeControl will announce itself on your network so {app} can find it.",
  "@onboardingConnectionSubtitleNetwork": {"placeholders": {"app": {"type": "String"}}},
  "onboardingThenInApp": "Then in {app}",
  "@onboardingThenInApp": {"placeholders": {"app": {"type": "String"}}},
  "onboardingFullSetupGuide": "Full {app} setup guide",
  "@onboardingFullSetupGuide": {"placeholders": {"app": {"type": "String"}}},
  "onboardingGuideMyWhoosh1": "Open the Connection screen in MyWhoosh",
  "onboardingGuideMyWhoosh2": "Tap the OpenBikeControl icon in the top right",
  "onboardingGuideMyWhoosh3": "Tap Yes in the popup to let BikeControl connect",
  "onboardingGuideRouvy1": "Open Rouvy and go to the connection screen",
  "onboardingGuideRouvy2": "BikeControl appears as an available controller — connect and ride",
  "onboardingGuideTp1": "Open the connection screen in TrainingPeaks Virtual",
  "onboardingGuideTp2": "Pair with BikeControl",
  "onboardingGuideTp3": "Map the actions you want to your buttons",
  "onboardingGuideStrappo1": "Open Strappo's connection screen",
  "onboardingGuideStrappo2": "Pair with BikeControl over the OpenBikeControl protocol",
  "onboardingGuideGeneric1": "Open {app}'s connection screen",
  "@onboardingGuideGeneric1": {"placeholders": {"app": {"type": "String"}}},
  "onboardingGuideGeneric2": "Pair with BikeControl",
  "onboardingPairAsTrainer": "Pair BikeControl as your trainer",
  "onboardingPairAsTrainerBody": "On {app}'s pairing screen, don't pick your trainer directly — pick the BikeControl entry. That's what carries your gears across.",
  "@onboardingPairAsTrainerBody": {"placeholders": {"app": {"type": "String"}}},
  "onboardingVirtualTrainerGears": "Virtual trainer · {gears} gears",
  "@onboardingVirtualTrainerGears": {"placeholders": {"gears": {"type": "String"}}},
  "onboardingPairAsTrainerWarning": "If you pair {trainer} directly, {app} takes the raw power and your BikeControl gears won't apply.",
  "@onboardingPairAsTrainerWarning": {"placeholders": {"trainer": {"type": "String"}, "app": {"type": "String"}}},
  "onboardingFinishSetup": "Finish setup",
```

Run: `flutter pub global run intl_utils:generate`

- [ ] **Step 5: Snapshot** `onboarding_step_connection` for MyWhoosh + `Target.otherDevice`, `hasTrainer: false`, width 380 (network images will fail in tests — the `errorBuilder` hides them, that's the offline behavior working). And one with `hasTrainer: true, trainerName: 'KICKR CORE'`. Run + view.

- [ ] **Step 6: Commit** — `git commit -m "feat(onboarding): step 5 connection methods and in-app setup guide"`

---

### Task 12: Step 6 — ready, test mode, completion

**Files:**
- Create: `lib/pages/onboarding/steps/step_done.dart`
- Modify: `lib/pages/onboarding/onboarding_page.dart`
- Modify: `lib/i10n/intl_en.arb`
- Test: extend `test/onboarding_snapshot_test.dart`

**Interfaces:**
- Consumes: `SubscriptionPage` opened via `openDrawer(context:, builder: (c) => SubscriptionPage(), position: OverlayPosition.end)` (menu.dart:42-48), `Settings.onboardingStateCompleted` + `setOnboardingState`, `IAPManager.instance.isPurchased` (`ValueNotifier<bool>` — grep exact name in `lib/utils/iap/`; skip the paywall button when already purchased).
- Produces: `Widget onboardingDoneBody(BuildContext context, {required SupportedApp app, required String? controllerName, required String? trainerName, required bool reduceMotion})`.

- [ ] **Step 1: Implement**

```dart
// lib/pages/onboarding/steps/step_done.dart
import 'package:bike_control/utils/i18n_extension.dart';
import 'package:bike_control/utils/keymap/apps/supported_app.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

Widget onboardingDoneBody(BuildContext context,
    {required SupportedApp app, required String? controllerName, required String? trainerName, required bool reduceMotion}) {
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
          Expanded(child: Text(title).small.semibold),
          Text(sub).xSmall.muted,
        ]),
      ),
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
          Text(context.i18n.onboardingTestModeTitle).small.semibold,
        ]),
        Gap(6),
        Text(trainerName != null
                ? context.i18n.onboardingTestModeBodyVs
                : context.i18n.onboardingTestModeBody)
            .xSmall,
      ]),
    ),
  ]);
}

class _SuccessBurst extends StatelessWidget {
  const _SuccessBurst({required this.reduceMotion});
  final bool reduceMotion;

  @override
  Widget build(BuildContext context) {
    const success = Color(0xFF22C55E);
    return Container(
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
  }
}
```

(If time allows, wrap `_SuccessBurst` in a `TweenAnimationBuilder<double>` scale-in `0.6 → 1.0` with `Curves.easeOutBack` gated on `!reduceMotion` — mirror `StageBadge`'s pop-in in `guided_operation_sheet.dart:43-77`.)

- [ ] **Step 2: Wire + completion**

Body case: `controllerName: core.connection.controllerDevices.where((d) => d.isConnected).firstOrNull?.name`, `trainerName:` the bridged proxy's name (as in Task 11), `reduceMotion: MediaQuery.of(context).disableAnimations`. Footer:

```dart
        OnboardingStep.done => [
            if (!IAPManager.instance.isPurchased.value)
              PrimaryButton(
                onPressed: () async {
                  await core.settings.setOnboardingState(Settings.onboardingStateCompleted);
                  if (!mounted) return;
                  openDrawer(context: context, builder: (c) => SubscriptionPage(), position: OverlayPosition.end);
                },
                child: Row(children: [Icon(LucideIcons.award, size: 16), Gap(8), Text(context.i18n.onboardingSeeProOptions)]),
              ),
            GhostButton(
              onPressed: () async {
                await core.settings.setOnboardingState(Settings.onboardingStateCompleted);
                if (mounted) Navigator.of(context).pop();
              },
              child: Text(context.i18n.onboardingDoneStartRiding),
            ),
          ],
```

Also: back is hidden on `done` (`onBack: null`) — setup is committed, going back would be confusing.

- [ ] **Step 3: ARB** (design copy)

```json
  "onboardingDoneTitle": "You're ready to ride",
  "onboardingYourController": "Your controller",
  "onboardingDoneSubtitle": "{controller} is connected to {app}.",
  "@onboardingDoneSubtitle": {"placeholders": {"controller": {"type": "String"}, "app": {"type": "String"}}},
  "onboardingDoneSubtitleBridged": "{controller} is connected to {app}, and your trainer is bridged through BikeControl.",
  "@onboardingDoneSubtitleBridged": {"placeholders": {"controller": {"type": "String"}, "app": {"type": "String"}}},
  "onboardingSummaryReady": "Ready",
  "onboardingSummaryBridged": "Bridged",
  "onboardingTestModeTitle": "You're in test mode",
  "onboardingTestModeBody": "Ride now and check everything works. Test mode limits you to a daily command budget — enough to prove the connection, not a whole session.",
  "onboardingTestModeBodyVs": "Ride now and check everything works. Test mode limits you to a daily command budget and limited virtual shifting per day — enough to prove the connection, not a whole session.",
  "onboardingSeeProOptions": "See Pro & Base options",
  "onboardingDoneStartRiding": "Done — start riding",
```

Run: `flutter pub global run intl_utils:generate`

- [ ] **Step 4: Snapshot** with and without trainer, width 380. Run + view. Also run `flutter test test/onboarding_trigger_test.dart test/onboarding_models_test.dart` (all still green).

- [ ] **Step 5: Commit** — `git commit -m "feat(onboarding): step 6 success, test mode and completion"`

---

### Task 13: Copy refresh, CHANGELOG, full verification sweep

**Files:**
- Modify: `lib/i10n/intl_en.arb` (existing keys, English values only)
- Modify: `CHANGELOG.md`
- Test: all onboarding test files

- [ ] **Step 1: Copy refresh** — compare the design's improved wording against existing English strings and update VALUES in place (keys unchanged, other locales untouched — Localazy retranslates):
  - The `clickV2Onboarding_*` set: adopt the design's pros/cons ("No Zwift unlock — ever", "Works right away, no second app", "Drops out a minute after your last button press — reconnects on its own", "Only the left controller sends button presses", "Both controllers work", "No restarts during your ride", "Needs unlocking with the Zwift app every 24 hours", "The unlock can be flaky") where the existing values are clearly worse. Judge per string; skip strings that already read fine.
  - `sramSetupIntro`: design copy — "BikeControl backs up your current shifter configuration and disables the derailleur's own shifting, so the paddles send button presses instead. You can restore it anytime."
  - `sramAuthorize*` body: "Hold the AXS button on your derailleur until its light flashes, then tap Retry." (if the existing string differs meaningfully).
  - `scanningForDevices`: leave as-is (the wizard shows its own subtitle; the long existing string still fits the home screen).

  Run: `flutter pub global run intl_utils:generate`

- [ ] **Step 2: CHANGELOG.md** — add an entry under the current unreleased version: "New: a guided setup wizard on first launch — pick your app, connect your controller and trainer, and link the app step by step. Re-run it anytime via Menu → Setup guide."

- [ ] **Step 3: Full verification**

```bash
flutter analyze
flutter test test/onboarding_trigger_test.dart test/onboarding_models_test.dart
flutter test test/onboarding_snapshot_test.dart
flutter test test/sram_states_snapshot_test.dart   # copy refresh didn't break the SRAM sheet
```

All green. Review every PNG under `build/snapshots/onboarding_*` at both widths against the design kit; list discrepancies and fix or accept explicitly.

- [ ] **Step 4: Manual smoke (macOS)** — `flutter run -d macos`, then: Menu → Setup guide → walk all six steps (skip controller + trainer if no hardware nearby), verify: progress rail on desktop width, window resize below 800 switches to mobile shell, Help sheet opens per step, Finish → Done returns to home, re-open Setup guide starts at step 1 with current settings pre-selected. Check no console errors.

- [ ] **Step 5: Commit**

```bash
git add lib/i10n/intl_en.arb lib/gen CHANGELOG.md
git commit -m "feat(onboarding): refresh existing copy from the design, changelog entry"
```

---

## Self-Review (done at plan time)

- **Spec coverage:** trigger + migration (T1), shell mobile/desktop (T2), help + permission-denied sheets (T3), step 1 (T5), step 2 (T6), step 3 all phases + sub-flows + button hint (T8, T9), step 4 (T10), step 5 incl. guides + bridge card (T11), step 6 + paywall + completion (T12), copy refresh + QA (T13), shared-logic refactors (T4, T7). Reduced motion, `recordError`, `screenshotMode`, l10n rules in Global Constraints.
- **Known judgment calls for implementers:** exact shadcn text-extension names (`.h4`, `.withColor`) and `CircularProgressIndicator(size:)` — verify against neighboring files before use, the plan flags each site; the "no method enabled" predicate (T11) and `IAPManager.isPurchased` (T12) are specified by reference to the exact file/lines that already use them.
- **Type consistency:** `onboardingShell` signature fixed in T2 and only consumed thereafter; `ControllerPhase` defined once (T2), used in T8/T9; `onboardingTrainerBridged` defined T10, reused T11/T12; `applyTrainerAppSelection`/`applyTargetSelection` defined T4, consumed T5/T6; `buildConnectionMethodTiles` defined T7, consumed T11.
