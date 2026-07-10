# ButtonEditor: show local connection-method actions when disabled, with an enable dialog

**Date:** 2026-07-02
**Status:** Approved (design)

## Goal

In the ButtonEditor (`lib/pages/button_edit.dart`), show the Local connection
method's action cards wherever the Local method is *available*, even when it is
not enabled. Tapping such a card while Local is disabled opens a dialog that
lets the user enable the Local connection method inline (running the same
permission flow the connection tile uses), rather than the current toast.

## Current behavior

The "Local / Remote" section is gated by `if (core.logic.showLocalRemoteOptions)`
(lines ~269–547). It contains four local action cards:

- **Simulate keyboard shortcut** (line ~273) — hidden entirely when Local is
  not enabled: its `if` requires
  `supportedModes.contains(keyboard) && (getLocalEnabled() || getRemoteKeyboardControlEnabled())`.
- **Simulate touch / mouse** (line ~291) — hidden similarly, requiring
  `supportedModes.contains(touch) && (getLocalEnabled() || getRemoteControlEnabled())`.
- **Simulate media key** (line ~316) — shown whenever `supportedModes.contains(media)`;
  tapping while disabled fires `buildToast(enableLocalConnectionMethodFirst)`.
- **Android system action** (line ~490) — shown when
  `showLocalControl && actionHandler is AndroidActions`; tapping while disabled
  fires the same toast.

Keyboard/touch taps route through `_showModeDropdown(context, mode)`, which
holds a shared `isEnabled` check and the toast (lines ~1344–1355). The media
and Android cards do the enabled-check inline in their `onPressed`.

## Key facts that make this clean

1. `core.logic.showLocalControl` is `getLastTarget()?.connectionType == local && (macOS || Windows || Android)`
   — it means "Local is *available*", independent of `getLocalEnabled()`. The
   whole section already renders whenever `showLocalControl` is true, so
   "where available" is already bounded by the enclosing section.
2. `media` is present in `supportedModes` only for the local handlers
   (`DesktopActions`, `AndroidActions`), never `RemoteActions`
   (`{touch, keyboard}`). So the media card already implies `showLocalControl`,
   and the enable-Local dialog can only ever surface in a genuinely-local
   context.
3. Enabling Local requires one platform permission —
   `AccessibilityRequirement` on Android, `KeyboardRequirement` on
   desktop/macOS (`core.permissions.getLocalControlRequirements()`).

## Changes

### 1. Card visibility (show where Local is available, even if disabled)

- Keyboard card `if`:
  `supportedModes.contains(keyboard) && (core.logic.showLocalControl || core.logic.isRemoteKeyboardControlEnabled)`
- Touch card `if`:
  `supportedModes.contains(touch) && (core.logic.showLocalControl || core.logic.isRemoteControlEnabled)`
- Media & Android cards: visibility unchanged.

Rationale: in a remote-only context (`showLocalControl == false`) a card now
only appears when its remote counterpart is enabled — which means it is already
usable, so the enable-Local dialog is never reached there. The dialog only
appears when `showLocalControl` is true (Local genuinely available), so it is
always valid.

The cards' existing `isActive` expressions already include `getLocalEnabled()`,
so a visible-but-disabled card renders **inactive** — no change needed there.

### 2. Shared enable-Local flow

Add a top-level function in `lib/widgets/ui/connection_method.dart`, beside
`openPermissionSheet`:

```dart
/// Prompts for any missing local-control permissions, enables the Local
/// connection method, and returns whether Local is enabled afterwards.
Future<bool> enableLocalControl(BuildContext context) async { ... }
```

Behavior mirrors `LocalTile.onChange` + `ConnectionMethod`'s requirement flow:

1. `requirements = core.permissions.getLocalControlRequirements()`.
2. Collect `notDone` = requirements whose `getStatus()` is false.
3. If `notDone` is non-empty: `await openPermissionSheet(context, notDone)`,
   then re-check; if still not all granted, return `false`.
4. `core.settings.setLocalEnabled(true)`.
5. Update `core.local` state: on `core.logic.canRunAndroidService`, set
   `isStarted`/`isConnected` from `isAndroidServiceRunning()`; otherwise set
   both `true`.
6. `core.connection.signalNotification(LogNotification('Local Control: true'))`.
7. Return `core.settings.getLocalEnabled()`.

Guard every `context` use after an `await` with `context.mounted`.

### 3. Enable dialog

Add a private `Future<bool> _promptEnableLocal(BuildContext context)` in
`_ButtonEditPageState`. A shadcn `AlertDialog` matching the existing dialogs in
this file (`showDialog<bool>` + `Navigator.pop(context, …)`):

- Title: `enableLocalConnectionMethodTitle`.
- Content: `enableLocalConnectionMethodDescription`.
- Actions: **Cancel** (`Navigator.pop(context, false)`) and **Enable**
  (`Navigator.pop(context, true)`).

If the dialog returns `true`, call `enableLocalControl(context)`; on success and
while `mounted`, `setState(() {})` so the cards re-render as enabled. Return the
result.

### 4. Route disabled taps to the dialog (replacing the toasts)

- `_showModeDropdown` (keyboard/touch): replace the `if (!isEnabled) return buildToast(...)`
  branch with: `await _promptEnableLocal(context)`; if it returns false or
  `!context.mounted`, return; otherwise continue to the existing dropdown logic
  (restructure the current `else if` into a fall-through).
- Media card `onPressed`: replace the toast branch with the same prompt; on
  success, continue to show the media-keys dropdown.
- Android-system-action card `onPressed`: replace the toast branch with the
  same prompt; on success, continue to show the Android-actions dropdown.

### Out of scope

The "Assistant" and "Broadcast intent" cards (lines ~549–588) live outside the
Local/Remote section, always show on Android, and do not gate on the enabled
flag today — left unchanged.

### i18n

Add to `lib/i10n/intl_en.arb` and regenerate `lib/gen/l10n.dart` via flutter_intl
(`arb_dir: lib/i10n`, `class_name: AppLocalizations`, `output_dir: lib/gen`):

- `enableLocalConnectionMethodTitle` — e.g. "Enable Local connection method?"
- `enableLocalConnectionMethodDescription` — e.g. "This action uses the Local
  connection method, which isn't enabled yet. Enable it to use this action."
- `enable` — "Enable" (reuse existing `cancel`).

Other-locale arb files fall back to English until translated.

## Testing

- Widget test following `test/pages/proxy_device_details_test.dart`'s pump
  pattern: with Local disabled, a local target, and `DesktopActions`
  (`{keyboard, touch, media}`), assert the keyboard/touch/media cards **render**
  (previously keyboard/touch would be absent), and that tapping a disabled card
  **shows the enable dialog**. Tapping **Cancel** dismisses it and leaves Local
  disabled.
- The Enable *success* path depends on the platform permission requirements
  (Accessibility/Keyboard), which are awkward to fake in a widget test. Verify
  that path end-to-end by running the app (`/verify`) rather than mocking the
  permission channel.

## Files touched

- `lib/pages/button_edit.dart` — visibility conditions, `_promptEnableLocal`,
  disabled-tap routing in `_showModeDropdown` + media/Android `onPressed`.
- `lib/widgets/ui/connection_method.dart` — `enableLocalControl` helper.
- `lib/i10n/intl_en.arb` + generated `lib/gen/l10n.dart`.
- `test/…` — new widget test for the ButtonEditor local cards + dialog.
