# ButtonEditor: Show Local Actions When Disabled + Enable Dialog — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** In the ButtonEditor, always show the Local connection method's action cards where Local is available, and let the user enable Local inline via a dialog when they tap a card while Local is disabled.

**Architecture:** Extract the keyboard/touch card visibility into two testable `CoreLogic` getters. Add a shared `enableLocalControl(context)` helper (next to `openPermissionSheet`) that runs the permission flow and enables Local. Add a `_promptEnableLocal` dialog in the ButtonEdit page and route the three disabled-tap sites (keyboard/touch via `_showModeDropdown`, media card, Android system-action card) through it, replacing the old toast.

**Tech Stack:** Flutter, Dart, `shadcn_flutter` (dialogs/buttons), `flutter_intl`/`intl_utils` (localization), `flutter_test`.

## Global Constraints

- Localization uses `flutter_intl`: add strings to `lib/i10n/intl_en.arb`, then regenerate `lib/gen/l10n.dart` with `dart run intl_utils:generate`. Access strings via `context.i18n.<key>` (equals `AppLocalizations.of(context)`).
- Match the existing dialog pattern in `lib/pages/button_edit.dart`: `showDialog<T>(context: ..., builder: ...)` returning an `AlertDialog(title:, content:, actions: [...])`, dismissed with `Navigator.pop(context, value)`.
- After any `await`, guard `BuildContext` use with `context.mounted` and `State` use with `mounted`.
- Unit tests run on a **desktop host (macOS/Windows)**, where `core.logic.showLocalControl` can be true. CI (`build.yml`) does not run `flutter test`; the developer runs tests locally on macOS. This matches existing tests (e.g. `test/modifier_keys_test.dart`) that assume `Target.thisDevice`/desktop.
- Commit after each task.
- Do not modify the "Assistant" / "Broadcast intent" cards (lines ~549–588) — out of scope.

---

## File Structure

- `lib/i10n/intl_en.arb` — add 3 localization strings (Task 1).
- `lib/gen/l10n.dart` — generated; regenerated in Task 1 (do not hand-edit).
- `lib/utils/core.dart` — add `showLocalKeyboardCard` / `showLocalTouchCard` getters to `CoreLogic` (Task 2).
- `test/utils/local_action_cards_visibility_test.dart` — new unit test for the getters (Task 2).
- `lib/widgets/ui/connection_method.dart` — add top-level `enableLocalControl(context)` helper (Task 3).
- `lib/pages/button_edit.dart` — add `_promptEnableLocal`, wire the two getters into card visibility, route the three disabled-tap sites through the dialog, add `connection_method.dart` import (Task 4).

---

## Task 1: Add localization strings and regenerate

**Files:**
- Modify: `lib/i10n/intl_en.arb`
- Regenerate: `lib/gen/l10n.dart` (via command)

**Interfaces:**
- Consumes: nothing.
- Produces: `AppLocalizations` getters `enable`, `enableLocalConnectionMethodTitle`, `enableLocalConnectionMethodDescription` (used by Task 4).

- [ ] **Step 1: Add the three strings to the English ARB**

In `lib/i10n/intl_en.arb`, the existing line reads:

```json
  "enableLocalConnectionMethodFirst": "Enable Local Connection method, first.",
```

Insert these three keys immediately **before** that line:

```json
  "enable": "Enable",
  "enableLocalConnectionMethodDescription": "This action uses the Local connection method, which isn't enabled yet. Enable it to use this action.",
  "enableLocalConnectionMethodTitle": "Enable Local connection method?",
```

(Order is cosmetic — the file is alphabetized; these sit next to the existing `enableLocalConnectionMethodFirst`.)

- [ ] **Step 2: Regenerate the localization Dart**

Run: `dart run intl_utils:generate`
Expected: exit 0; `lib/gen/l10n.dart` is rewritten with getters for the new keys.

- [ ] **Step 3: Verify the getters exist**

Run: `grep -n "enableLocalConnectionMethodTitle\|enableLocalConnectionMethodDescription\|String get enable\b" lib/gen/l10n.dart`
Expected: matches for `enableLocalConnectionMethodTitle`, `enableLocalConnectionMethodDescription`, and an `enable` getter.

- [ ] **Step 4: Analyze**

Run: `flutter analyze lib/gen/l10n.dart`
Expected: No issues (for that file).

- [ ] **Step 5: Commit**

```bash
git add lib/i10n/intl_en.arb lib/gen/l10n.dart
git commit -m "i18n(button-editor): add enable-local dialog strings"
```

---

## Task 2: Extract card-visibility getters into CoreLogic (TDD)

**Files:**
- Test: `test/utils/local_action_cards_visibility_test.dart` (create)
- Modify: `lib/utils/core.dart` (add getters to `class CoreLogic`)

**Interfaces:**
- Consumes: existing `CoreLogic` members `showLocalControl`, `isRemoteControlEnabled`, `isRemoteKeyboardControlEnabled`, and `core.actionHandler.supportedModes`.
- Produces: `bool get showLocalKeyboardCard` and `bool get showLocalTouchCard` on `CoreLogic`, reached via `core.logic.showLocalKeyboardCard` / `core.logic.showLocalTouchCard`.

Background (verified):
- `core.settings.setLastTarget(Target.thisDevice)` → `ConnectionType.local` → `initializeActions` sets `core.actionHandler = DesktopActions()` (`supportedModes == {keyboard, touch, media}`), and `showLocalControl == true` on macOS/Windows.
- `core.settings.setLastTarget(Target.otherDevice)` → `ConnectionType.remote` → `RemoteActions()` (`{touch, keyboard}`), `showLocalControl == false`, `showRemote == true`.
- `isRemoteKeyboardControlEnabled == getRemoteKeyboardControlEnabled() && showRemote`; `isRemoteControlEnabled == getRemoteControlEnabled() && showRemote`.

- [ ] **Step 1: Write the failing test**

Create `test/utils/local_action_cards_visibility_test.dart`:

```dart
import 'dart:ui';

import 'package:bike_control/gen/l10n.dart';
import 'package:bike_control/main.dart';
import 'package:bike_control/utils/core.dart';
import 'package:bike_control/utils/keymap/apps/my_whoosh.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> main() async {
  await AppLocalizations.load(const Locale('en'));

  // These getters gate on desktop-local availability (showLocalControl is only
  // true on macOS/Windows/Android). This suite is meaningful on a desktop host.
  final isDesktop = !kIsWeb && (defaultTargetPlatform == TargetPlatform.macOS ||
      defaultTargetPlatform == TargetPlatform.windows);

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
    screenshotMode = false;
    await core.settings.init();
    await core.settings.reset();
    core.settings.setTrainerApp(MyWhoosh());
    core.settings.setKeyMap(MyWhoosh());
  });

  group('local action card visibility', () {
    test('keyboard/touch cards show for local target even when Local is disabled', () async {
      if (!isDesktop) return; // local control unavailable off-desktop
      await core.settings.setLastTarget(Target.thisDevice);
      core.settings.setLocalEnabled(false);

      expect(core.logic.showLocalControl, isTrue);
      expect(core.logic.showLocalKeyboardCard, isTrue);
      expect(core.logic.showLocalTouchCard, isTrue);
    });

    test('remote target: cards hidden unless the matching remote method is enabled', () async {
      await core.settings.setLastTarget(Target.otherDevice);
      core.settings.setLocalEnabled(false);
      core.settings.setRemoteControlEnabled(false);
      core.settings.setRemoteKeyboardControlEnabled(false);

      expect(core.logic.showLocalControl, isFalse);
      expect(core.logic.showLocalKeyboardCard, isFalse);
      expect(core.logic.showLocalTouchCard, isFalse);
    });

    test('remote target: keyboard card shows when remote keyboard control is enabled', () async {
      await core.settings.setLastTarget(Target.otherDevice);
      core.settings.setRemoteKeyboardControlEnabled(true);

      expect(core.logic.isRemoteKeyboardControlEnabled, isTrue);
      expect(core.logic.showLocalKeyboardCard, isTrue);
    });

    test('remote target: touch card shows when remote control is enabled', () async {
      await core.settings.setLastTarget(Target.otherDevice);
      core.settings.setRemoteControlEnabled(true);

      expect(core.logic.isRemoteControlEnabled, isTrue);
      expect(core.logic.showLocalTouchCard, isTrue);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/utils/local_action_cards_visibility_test.dart`
Expected: FAIL — `core.logic.showLocalKeyboardCard` / `showLocalTouchCard` are undefined (compile error).

- [ ] **Step 3: Add the getters**

In `lib/utils/core.dart`, inside `class CoreLogic`, immediately after the `showLocalRemoteOptions` getter (currently lines ~316–318), add:

```dart
  /// The "Simulate keyboard shortcut" card is shown when the keyboard mode is
  /// supported and either Local is available (may be disabled — tapping then
  /// prompts to enable it) or remote-keyboard control is already enabled.
  bool get showLocalKeyboardCard =>
      core.actionHandler.supportedModes.contains(SupportedMode.keyboard) &&
      (showLocalControl || isRemoteKeyboardControlEnabled);

  /// The "Simulate touch / mouse" card is shown when the touch mode is
  /// supported and either Local is available or remote control is enabled.
  bool get showLocalTouchCard =>
      core.actionHandler.supportedModes.contains(SupportedMode.touch) &&
      (showLocalControl || isRemoteControlEnabled);
```

(`SupportedMode` is already in scope in `core.dart`; if analysis reports it missing, add `import 'package:bike_control/utils/actions/base_actions.dart';` — verify with Step 5.)

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/utils/local_action_cards_visibility_test.dart`
Expected: PASS (all 4 tests; the desktop-only test runs on macOS/Windows).

- [ ] **Step 5: Analyze**

Run: `flutter analyze lib/utils/core.dart`
Expected: No issues.

- [ ] **Step 6: Commit**

```bash
git add lib/utils/core.dart test/utils/local_action_cards_visibility_test.dart
git commit -m "feat(core): showLocalKeyboardCard/showLocalTouchCard visibility getters"
```

---

## Task 3: Add `enableLocalControl` helper

**Files:**
- Modify: `lib/widgets/ui/connection_method.dart` (add imports + top-level function beside `openPermissionSheet`)

**Interfaces:**
- Consumes: existing `openPermissionSheet(BuildContext, List<PlatformRequirement>)` in the same file; `core.permissions.getLocalControlRequirements()`, `core.settings.setLocalEnabled/getLocalEnabled`, `core.logic.canRunAndroidService/isAndroidServiceRunning`, `core.local.isStarted/isConnected`, `core.connection.signalNotification`, `LogNotification`.
- Produces: `Future<bool> enableLocalControl(BuildContext context)` — returns whether Local is enabled after the flow.

No unit test: the requirement `getStatus()` (`KeyboardRequirement`/`AccessibilityRequirement`) calls a platform channel (`keypress_simulator` / accessibility), so the happy path is exercised via `/verify` in Task 4. This task's gate is compile + analyze.

- [ ] **Step 1: Add imports**

At the top of `lib/widgets/ui/connection_method.dart`, add these imports (keep the list alphabetized among the existing `package:bike_control/...` imports):

```dart
import 'package:bike_control/bluetooth/messages/notification.dart';
import 'package:bike_control/utils/core.dart';
```

- [ ] **Step 2: Add the helper**

At the **end** of `lib/widgets/ui/connection_method.dart` (after the existing `openPermissionSheet` function), add:

```dart
/// Prompts for any missing local-control permissions, enables the Local
/// connection method, and returns whether Local is enabled afterwards.
///
/// Mirrors the enable path in [LocalTile.onChange] + [ConnectionMethod]'s
/// requirement flow so a caller (e.g. the ButtonEditor) can enable Local
/// inline instead of sending the user to the connection settings.
Future<bool> enableLocalControl(BuildContext context) async {
  final requirements = core.permissions.getLocalControlRequirements();
  final notDone = <PlatformRequirement>[];
  for (final requirement in requirements) {
    if (!await requirement.getStatus()) {
      notDone.add(requirement);
    }
  }
  if (notDone.isNotEmpty) {
    if (!context.mounted) return false;
    await openPermissionSheet(context, notDone);
    for (final requirement in notDone) {
      if (!await requirement.getStatus()) {
        return false;
      }
    }
  }

  core.settings.setLocalEnabled(true);
  if (core.logic.canRunAndroidService) {
    final running = await core.logic.isAndroidServiceRunning();
    core.local.isStarted.value = running;
    core.local.isConnected.value = running;
  } else {
    core.local.isStarted.value = true;
    core.local.isConnected.value = true;
  }
  core.connection.signalNotification(LogNotification('Local Control: true'));
  return core.settings.getLocalEnabled();
}
```

- [ ] **Step 3: Analyze**

Run: `flutter analyze lib/widgets/ui/connection_method.dart`
Expected: No issues (no unused-import warnings; `PlatformRequirement` resolves via the existing `platform.dart` import).

- [ ] **Step 4: Commit**

```bash
git add lib/widgets/ui/connection_method.dart
git commit -m "feat(connection): enableLocalControl helper for inline enabling"
```

---

## Task 4: Enable dialog + wire visibility + route disabled taps

**Files:**
- Modify: `lib/pages/button_edit.dart`

**Interfaces:**
- Consumes: `core.logic.showLocalKeyboardCard` / `showLocalTouchCard` (Task 2); `enableLocalControl(BuildContext)` (Task 3); existing `context.i18n.enable` / `enableLocalConnectionMethodTitle` / `enableLocalConnectionMethodDescription` (Task 1).
- Produces: `Future<bool> _promptEnableLocal(BuildContext context)` in `_ButtonEditPageState`; user-facing behavior change (cards always visible where Local is available; tapping-while-disabled shows the enable dialog).

- [ ] **Step 1: Add the `connection_method.dart` import**

In `lib/pages/button_edit.dart`, add (alphabetized among `package:bike_control/...` imports, e.g. right before `widgets/ui/colored_title.dart`):

```dart
import 'package:bike_control/widgets/ui/connection_method.dart';
```

- [ ] **Step 2: Add the `_promptEnableLocal` method**

In `_ButtonEditPageState` (e.g. directly above `Future<void> _showModeDropdown(...)`, currently ~line 1322), add:

```dart
  /// Asks the user whether to enable the Local connection method; on confirm,
  /// runs [enableLocalControl] and rebuilds so the local action cards reflect
  /// the new enabled state. Returns whether Local ended up enabled.
  Future<bool> _promptEnableLocal(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.i18n.enableLocalConnectionMethodTitle),
        content: Text(context.i18n.enableLocalConnectionMethodDescription),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.i18n.cancel),
          ),
          PrimaryButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(context.i18n.enable),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return false;
    final enabled = await enableLocalControl(context);
    if (enabled && mounted) setState(() {});
    return enabled;
  }
```

- [ ] **Step 3: Wire the keyboard card visibility**

In the "Local / Remote" section, the keyboard card currently begins (lines ~273–274):

```dart
                  if (core.actionHandler.supportedModes.contains(SupportedMode.keyboard) &&
                      (core.settings.getLocalEnabled() || core.settings.getRemoteKeyboardControlEnabled()))
```

Replace those two lines with:

```dart
                  if (core.logic.showLocalKeyboardCard)
```

- [ ] **Step 4: Wire the touch card visibility**

The touch card currently begins (lines ~291–292):

```dart
                  if (core.actionHandler.supportedModes.contains(SupportedMode.touch) &&
                      (core.settings.getLocalEnabled() || core.settings.getRemoteControlEnabled()))
```

Replace those two lines with:

```dart
                  if (core.logic.showLocalTouchCard)
```

- [ ] **Step 5: Route the keyboard/touch dropdown through the dialog**

In `_showModeDropdown` (currently ~lines 1351–1355), replace:

```dart
    if (!isEnabled) {
      return buildToast(
        title: AppLocalizations.of(context).enableLocalConnectionMethodFirst,
      );
    } else if (actionsWithInGameAction.isNotEmpty) {
```

with:

```dart
    if (!isEnabled) {
      final enabled = await _promptEnableLocal(context);
      if (!enabled || !context.mounted) return;
    }
    if (actionsWithInGameAction.isNotEmpty) {
```

(The `else { _editAction(supportedMode); }` tail is unchanged. After enabling, the same dropdown/`_editAction` path now runs.)

- [ ] **Step 6: Route the media-key card through the dialog**

In the media-key card's `onPressed` (currently ~lines 329–334), replace:

```dart
                        onPressed: () {
                          if (!core.settings.getLocalEnabled()) {
                            buildToast(
                              title: AppLocalizations.of(context).enableLocalConnectionMethodFirst,
                            );
                          } else {
                            showDropdown(
```

with:

```dart
                        onPressed: () async {
                          if (!core.settings.getLocalEnabled()) {
                            final enabled = await _promptEnableLocal(context);
                            if (!enabled || !context.mounted) return;
                          }
                          showDropdown(
```

Then delete the now-orphaned closing brace `}` that used to close the `else` block — it is the lone `}` immediately before the `},` that closes this `onPressed` (originally ~line 486, between the media `showDropdown(...)`'s closing `);` and the `},`). After the edit the tail should read:

```dart
                            );
                        },
                      ),
```

(not `);` → `}` → `},`).

- [ ] **Step 7: Route the Android system-action card through the dialog**

In the Android system-action card's `onPressed` (currently ~lines 508–511), replace:

```dart
                        onPressed: () {
                          if (!core.settings.getLocalEnabled()) {
                            buildToast(title: context.i18n.enableLocalConnectionMethodFirst);
                          } else {
                            showDropdown(
```

with:

```dart
                        onPressed: () async {
                          if (!core.settings.getLocalEnabled()) {
                            final enabled = await _promptEnableLocal(context);
                            if (!enabled || !context.mounted) return;
                          }
                          showDropdown(
```

Then delete the orphaned `}` that closed the former `else` (originally ~line 543, between this `showDropdown(...)`'s closing `);` and its `},`), so the tail reads:

```dart
                            );
                        },
                      ),
```

- [ ] **Step 8: Analyze (brace balance + types)**

Run: `flutter analyze lib/pages/button_edit.dart`
Expected: No issues. (A mismatched brace from Step 6/7 surfaces here as a syntax error — fix before continuing.)

- [ ] **Step 9: Run the existing test suite (no regressions)**

Run: `flutter test test/utils/local_action_cards_visibility_test.dart`
Expected: PASS.

- [ ] **Step 10: Verify end-to-end in the app**

Use the `/verify` skill (or run the app manually) on a desktop build with **Local disabled** and the target set to "this device":
1. Open a controller button → open the ButtonEditor for a trigger.
2. Confirm the **Simulate keyboard shortcut**, **Simulate touch/mouse**, and **Simulate media key** cards are visible (previously keyboard/touch were hidden) and render as **inactive**.
3. Tap one → the enable dialog appears (title "Enable Local connection method?"). Tap **Cancel** → dialog closes, Local stays disabled, card still inactive.
4. Tap again → **Enable** → the permission flow runs (Keyboard access on macOS); after granting, Local becomes enabled, the card becomes active, and the original action UI (dropdown / editor) proceeds.
5. Repeat the Android system-action card check on an Android build if available.

- [ ] **Step 11: Commit**

```bash
git add lib/pages/button_edit.dart
git commit -m "feat(button-editor): show local actions when disabled with enable dialog"
```

---

## Self-Review

**Spec coverage:**
- "Show keyboard/touch cards where available even if Local disabled" → Task 2 (getters) + Task 4 Steps 3–4 (wiring). ✅
- "Media & Android cards unchanged visibility, toast → dialog" → Task 4 Steps 6–7. ✅
- "Dialog asks to enable Local; Enable inline runs permission flow" → Task 3 (`enableLocalControl`) + Task 4 Step 2 (`_promptEnableLocal`). ✅
- "New i18n strings + regenerate" → Task 1. ✅
- "Out of scope: Assistant / Broadcast intent" → honored (untouched). ✅
- Testing: unit tests for visibility (Task 2); `/verify` for the enable/dialog path (Task 4 Step 10) — matches the spec's stated approach that the permission path is verified end-to-end rather than mocked. ✅
- Deviation from spec (documented): visibility predicates are extracted into `CoreLogic` getters (`showLocalKeyboardCard`/`showLocalTouchCard`) rather than left inline, purely for testability — the spec explicitly anticipated "borrowing the testable getter idea." Behavior is identical.

**Placeholder scan:** No TBD/TODO. Every code step shows complete code, except the two large unchanged `showDropdown(...)` bodies in Task 4 Steps 6–7, which are deliberately not reproduced — only the changed head + the single orphaned-brace deletion are specified, with `flutter analyze` (Step 8) as the balance check.

**Type consistency:** `showLocalKeyboardCard`/`showLocalTouchCard` (Task 2) are referenced identically in Task 4. `enableLocalControl(BuildContext) -> Future<bool>` (Task 3) is consumed as `await enableLocalControl(context)` in Task 4. `_promptEnableLocal(BuildContext) -> Future<bool>` is defined and called consistently. String keys `enable` / `enableLocalConnectionMethodTitle` / `enableLocalConnectionMethodDescription` match between Task 1 and Task 4.
