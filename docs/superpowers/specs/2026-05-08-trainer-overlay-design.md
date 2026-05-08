# Trainer Overlay — Design

**Date:** 2026-05-08
**Status:** Draft for review
**Goal:** Show the currently active virtual-shifting gear (and a few other live trainer values) on top of the user's trainer app, so riders can see their gear when BikeControl drives the smart trainer's shifting and the trainer app's own UI cannot reflect it.

## Problem

When BikeControl performs virtual shifting against a smart trainer, the trainer app (Zwift, MyWhoosh, Rouvy, etc.) does not know which BikeControl gear is currently active and cannot render it. Users have repeatedly reported that they have no way to see the current gear during a ride.

## Scope

In scope (v1):

- macOS, Windows, Android, iOS.
- Always-visible overlay UI showing **gear N/M** prominently.
- Mode indicator (SIM / ERG).
- Toggleable extras: power, cadence, ERG target power, gear ratio (off by default).
- Manual show/hide toggle.
- Persisted overlay state (enabled, position, selected fields).

Out of scope (v1):

- Linux desktop.
- Auto-detection of running trainer app to auto-toggle overlay.
- Interactive shift buttons inside the overlay (display only on Android/iOS; mode pill is interactive on desktop only).
- iPad Live Activities polish (the OS shows them on the lock screen only, which is useless during a ride — see caveats).
- Hotkey/global shortcut to toggle the overlay.

## Platform strategy

| Platform | Mechanism | Package |
|---|---|---|
| macOS | Compact-mode main window (frameless, transparent, always-on-top, draggable) | existing `window_manager` |
| Windows | Compact-mode main window (frameless, transparent, always-on-top, draggable) | existing `window_manager` |
| Android | OS-level system overlay over other apps | `flutter_overlay_window` |
| iOS | Live Activity (Dynamic Island compact/expanded + Lock Screen) | `live_activities` |

Rationale:

- **Desktop** uses the **same window** in compact mode rather than a second Flutter window. `window_manager` is already in `pubspec.yaml`. A second-window approach (`desktop_multi_window`) would require a separate Flutter engine and per-engine plugin registration, which is significant added surface area for a workout-time use case where the main UI does not need to remain visible.
- **Android** must use `SYSTEM_ALERT_WINDOW` via `flutter_overlay_window` because no in-process window can draw over another app on Android.
- **iOS** has no API for drawing over other apps. Live Activities (Dynamic Island + Lock Screen) are the only OS-sanctioned surface; the `live_activities` package is actively maintained and exposes Flutter→native update calls.

## Caveats (must be surfaced in UI)

- **Windows exclusive fullscreen:** an always-on-top window does not appear over a DirectX exclusive-fullscreen app. Users must run the trainer app in **borderless-windowed** mode. We surface a one-line tip in the toggle UI.
- **macOS Spaces / fullscreen:** to remain visible when the trainer app is fullscreened on its own Space, the overlay window must set `NSWindowCollectionBehaviorCanJoinAllSpaces` and `NSWindowCollectionBehaviorFullScreenAuxiliary`. If `window_manager` does not expose these, a small native shim in `macos/Runner` will set them on the `NSWindow`.
- **Android permission:** `SYSTEM_ALERT_WINDOW` requires the user to grant overlay permission in system settings. We must onboard this clearly.
- **iPad Live Activities:** iPad has no Dynamic Island and Live Activities surface only on the lock screen — riders running Zwift fullscreen on iPad gain no real value during the ride. We document this; we do not engineer around it.
- **iPhone Dynamic Island:** present from iPhone 14 Pro onward. Earlier iPhones get the Lock Screen presentation only.

## Architecture

```
lib/services/overlay/
  trainer_overlay_service.dart      // platform router; one of the three controllers
  desktop_overlay_controller.dart   // window_manager based; compact-mode toggle
  android_overlay_controller.dart   // flutter_overlay_window wrapper
  ios_overlay_controller.dart       // live_activities wrapper
lib/widgets/overlay/
  trainer_overlay_view.dart         // shared Flutter widget (desktop + Android isolate)
  overlay_entry_point.dart          // @pragma('vm:entry-point') for Android isolate
ios/Runner/
  TrainerActivity/                  // SwiftUI Widget Extension (Dynamic Island + Lock Screen)
lib/utils/settings/
  settings.dart                     // (extended) overlay enabled, position, fields
```

### `TrainerOverlayService`

Thin router. Single public surface:

```dart
abstract class TrainerOverlayController {
  Future<bool> show(FitnessBikeDefinition def);
  Future<void> hide();
  bool get isShowing;
}

class TrainerOverlayService {
  static TrainerOverlayController forCurrentPlatform();
}
```

Selection at runtime:

- `Platform.isMacOS || Platform.isWindows` → `DesktopOverlayController`
- `Platform.isAndroid` → `AndroidOverlayController`
- `Platform.isIOS` → `IosOverlayController`
- otherwise → no-op controller (Linux/web).

### Data flow

The overlay reads the same `ValueListenable`s already used by `gear_hero_card.dart`:

- `def.currentGear` (int)
- `def.maxGear` (int)
- `def.gearRatio` (double, opt-in)
- `def.trainerMode` (`TrainerMode`)
- `def.powerW` (`ValueListenable<int?>`)
- `def.cadenceRpm` (`ValueListenable<int?>`)
- `def.ergTargetPower` (int?)
- `def.targetPowerW` (int?)

All of these already exist on `FitnessBikeDefinition` and are consumed by `gear_hero_card.dart` and `proxy_device.dart` today — no new state plumbing required.

**Desktop:** the overlay widget tree (`TrainerOverlayView`) lives in the same Flutter isolate as the main app and listens directly to the listenables — no IPC needed.

**Android:** the overlay runs in a separate isolate launched by `flutter_overlay_window`. State is pushed from the main isolate to the overlay isolate via `FlutterOverlayWindow.shareData(json)`, **debounced to ~10 Hz**, on any of the listenables ticking. The overlay isolate decodes the JSON and updates a local `ValueNotifier` that drives the same `TrainerOverlayView` widget tree.

**iOS:** the controller subscribes to the same listenables, debounces to ~2 Hz (Live Activities throttle aggressively), and calls `updateActivity()` with a struct matching the SwiftUI `ActivityAttributes`/`ContentState`.

### Compact-mode mechanics (Desktop)

`DesktopOverlayController.show()`:

1. Capture current main window state (size, position, frameless flag).
2. Apply via `window_manager`: `setHasShadow(false)`, `setAlwaysOnTop(true)`, `setSize(220×140)`, `setBackgroundColor(transparent)`, `setMinimumSize`, `setSkipTaskbar(true)`, `setResizable(false)`, frameless.
3. macOS-only: invoke a `MethodChannel` to set `NSWindowCollectionBehavior` flags on `NSWindow` if `window_manager` does not expose them.
4. Replace the routed page with a `TrainerOverlayView` (achieved by switching a top-level `ValueNotifier<bool> overlayMode` that the app's root listens to).
5. Persist position via `window_manager`'s position events + `Settings.setOverlayPosition()`.

`hide()` reverses each step.

### Android permission flow

1. On first toggle, check `FlutterOverlayWindow.isPermissionGranted()`.
2. If denied, show a sheet explaining why we need the permission, with a "Grant in Settings" button that calls `FlutterOverlayWindow.requestPermission()`.
3. After grant, attempt to show the overlay. If still denied, keep the toggle off and the sheet visible.

### iOS Live Activity setup

1. Add `NSSupportsLiveActivities = true` to `ios/Runner/Info.plist`.
2. New target `TrainerActivity` (Widget Extension) with App Groups capability sharing with the main app.
3. SwiftUI views for: Lock Screen / Dynamic Island compact / minimal / expanded.
4. `IosOverlayController.show(def)` calls `LiveActivities.createActivity(...)` with the initial `ContentState`; subsequent ticks call `updateActivity(...)`.
5. `hide()` ends the activity with `endActivity(...)`.

## UI

### Compact overlay layout (~220×140, desktop and Android)

```
┌────────────────────────┐
│  ⚙ SIM      ☰ drag    │
│                        │
│      14 / 24           │
│                        │
│  178 W   86 rpm        │
└────────────────────────┘
```

- Top-left: mode pill (SIM/ERG). Tap to toggle on **desktop only**; static label on Android (touch UX inside overlay isolate is limited).
- Top-right: drag handle. On desktop, drag to move (calls `windowManager.startDragging()`). On Android, the package's built-in dragging is enabled.
- Center: gear `N/M`, large bold.
- Bottom: power and cadence (each can be hidden via settings).
- Long-press / right-click → small menu with "Hide overlay" and "Settings".

### iOS Dynamic Island presentations

- **Compact (leading/trailing):** small gear icon · "14/24".
- **Minimal:** gear number only.
- **Expanded:** gear `14/24` large, mode pill, power · cadence · ERG target.
- **Lock Screen:** same as Expanded, plus app name header.

### Settings additions

In `lib/pages/proxy_device_details.dart`, a new "Overlay" section (uses `SettingTile` for visual consistency with the rest of the page):

- **Show overlay** — `Switch` (per-platform behavior).
- **Fields** — multi-checkbox: Power, Cadence, ERG target, Gear ratio. (Gear and mode are always shown; cannot be unchecked.)
- **Tip card** (Windows + macOS): "Run the trainer app in borderless-windowed mode for the overlay to stay visible."
- **Android-only**: "Grant overlay permission" `Button.ghost` if not granted.

Persistence keys (extending `Settings`):

```dart
bool getOverlayEnabled();
Future<void> setOverlayEnabled(bool v);

Offset? getOverlayPosition();              // desktop
Future<void> setOverlayPosition(Offset p);

Set<OverlayField> getOverlayFields();      // {power, cadence, ergTarget, gearRatio}
Future<void> setOverlayFields(Set<OverlayField> fields);
```

`OverlayField` is an enum local to the overlay service.

## Error handling

- Android permission denied → toggle reverts to off, permission sheet stays visible until user dismisses.
- Desktop window restyle failure (rare) → revert all `window_manager` calls, show a transient toast.
- iOS Live Activity creation failure (e.g. Low Power Mode disables them) → toggle reverts to off, snackbar with the reason returned by ActivityKit.
- Trainer disconnect while overlay is up → overlay shows `--` for live values; gear value freezes at last known.

## Testing

- **Widget test** for `TrainerOverlayView` with mocked `ValueNotifier`s — covers gear/mode/field-toggle rendering.
- **Unit test** for `TrainerOverlayService.forCurrentPlatform()` selecting the right controller.
- **Manual test plan**:
  - macOS: Zwift in borderless window; verify always-on-top, drag, persisted position across app restart.
  - Windows: same with MyWhoosh.
  - Android: Zwift; first-run permission flow; overlay survives app backgrounding (already works per project's background-BLE setup).
  - iOS: iPhone 15 Pro — Dynamic Island compact + expanded; iPhone 13 — Lock Screen only; iPad — note in test plan that Live Activity is lock-screen-only and degraded by design.

No unit tests for l10n strings (per project convention).

## Dependencies added

```yaml
flutter_overlay_window: ^0.5.0   # Android only
live_activities: ^2.4.9          # iOS only
```

`window_manager` already present.

## Out of scope but worth flagging for later

- **Hotkey to toggle** (e.g. global F8 on desktop) — easy follow-up if users want it.
- **Auto-show on trainer-app focus** — would require window-title polling on desktop and `UsageStatsManager` on Android. Skip unless user demand emerges.
- **Color customization** — users may ask for high-contrast on bright trainer-app screens. Reserve for v2.
- **iPad-specific design** — would need a true overlay capability iOS does not provide, or a paired-Apple-Watch complication. Out of scope.
