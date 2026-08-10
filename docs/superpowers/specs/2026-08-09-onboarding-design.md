# BikeControl First-Run Onboarding — Design

**Date:** 2026-08-09 · **Status:** Approved by Jonas (brainstorming session)
**Design source:** claude.ai/design project `cb7f088e-e4b2-478e-a6d3-8a6dc466b911`,
`ui_kits/onboarding/` (mobile) and `ui_kits/onboarding-desktop/` (desktop).

## Problem

BikeControl's setup has real branching complexity — which trainer app, where that app
runs, which controller (some need extra unlock/config), whether to bridge a smart
trainer, and which connection method. Today a new user meets all of it at once as a
stack of cards on the home screen, and users are struggling to set it up. The design
replaces this with a six-step guided flow that asks one question at a time.

## Decisions (from the brainstorming session)

| Question | Decision |
| --- | --- |
| Trigger | Fresh installs (new `onboarding_completed` pref unset) **plus** a "Setup guide" menu entry to re-run anytime. Hidden in `screenshotMode`. |
| Device connection | **Keep auto-connect.** No tap-to-pick; the controller step shows devices appearing with live status as they auto-connect. No changes to `connection.dart` queue logic. |
| Paywall | Step 6's "See Pro & Base options" opens the **existing `SubscriptionPage`**. The design's Base/Pro comparison sheet is not built. |
| Architecture | **Full-screen route** (`MaterialPageRoute(fullscreenDialog: true)`) pushed over `Navigation` — same pattern as `showVirtualShiftingIntro`. BLE stack is live underneath, so scanning/connecting are real. |
| Sub-flows | Reuse existing: Click V2 → `UnlockPage`, SRAM → `SramGuidedSheet`. Reuse `SmoothWifiAnimation`, permission sheet, `SelectableCard`s, settings paths. Don't reinvent cards/scanning UI. |
| Copy | The design's wording is generally better than existing strings. New strings use design copy; where the design rewrote an existing string better (Click V2 pros/cons, SRAM intro, scan-empty tips), update the English source in place. Claude judges case by case. |

## Architecture

New directory `lib/pages/onboarding/`:

- `onboarding_page.dart` — route + state machine. One StatefulWidget owning
  `enum OnboardingStep { app, where, controller, virtualShifting, connection, done }`,
  a controller sub-phase (`permission | scanning | list | connected`), a trainer
  sub-state (`intro | connecting | connected`), and the accumulated choices.
- Step bodies are **pure functions of explicit state** (the `sramGuidedBody` pattern in
  `lib/bluetooth/devices/sram/sram_setup_sheet.dart`), so snapshot tests render exactly
  what production renders. Split step bodies into a few files mirroring the design kit
  (steps 1–2, step 3, steps 4–6, shared shell widgets) rather than one giant file.

### Entry points

- `Navigation.initState` post-frame callback (next to `_checkAndShowChangelog()` in
  `lib/pages/navigation.dart`): push when `!core.settings.getOnboardingCompleted()`
  and not `screenshotMode`.
- New pref `onboarding_completed` in `lib/utils/settings/settings.dart` following the
  existing `_fooKey` + `getFoo()/setFoo()` pattern. Set **only** when step 6 exits
  (Done or via paywall). Quitting mid-flow re-shows onboarding next launch; that is
  acceptable because settings are committed incrementally (see Data flow).
- **Existing-install migration:** the pref is also unset for users updating to this
  version, but the trigger decision is fresh installs only. On startup, if
  `getLastSeenVersion() != null` (an existing install, per the changelog mechanism)
  and `onboarding_completed` is unset, silently mark it completed. Existing users
  reach the flow only via the "Setup guide" menu entry.
- New "Setup guide" entry in the app menu pushes the same route for re-runs. A re-run
  starts at step 1 with current settings pre-selected, doubling as a reconfigure guide.

### Responsive shell

One breakpoint at **800** (matching `overview.dart`):

- **Mobile (<800):** header row (app icon · "Step n of 6" · Help pill, plus Skip when
  applicable), segmented progress bar (6 segments), scrollable body, sticky footer with
  full-width stacked buttons.
- **Desktop (≥800):** persistent left rail naming all six steps with done ✓ / active /
  upcoming states and a "Help & Support" button pinned at the bottom; centred
  `maxWidth: 640` body column; right-aligned footer action row. No progress bar.

Back behaviour: unwind within the step first (e.g. controller list → permission,
trainer connecting → intro), then previous step; step 1 has no back.

Sheets: sub-flows and help open via existing `openSheet`/`openDrawer`
(`OverlayPosition.bottom`); at desktop widths they get the width-capped
(`maxWidth` ~480–520) centred treatment `SramGuidedSheet` already implements.

Reduced motion: thread `MediaQuery.disableAnimations` through as `reduceMotion`, as the
SRAM sheet does.

## The six steps

### Step 1 — Which app do you ride with?

- Logo grid: **Official integrations** (from `SupportedApp.officialIntegration`,
  with logo assets) and **Also supported** (monogram tiles: Zwift, Biketerra,
  OpenBikeControl Compatible, Other). 3 columns on mobile, 5 on desktop.
- Note: official apps are tested/verified; others use generic connection methods.
- Selection writes through the same settings path as `ConfigurationPage`'s
  `TrainerAppSelect`. The grid is onboarding-only; the settings page keeps its
  dropdown.
- Footer: "Continue with $app" (disabled until a pick), per design.
- Tiles built from shadcn `SelectableCard`/`Button.card` — no new card primitives.

### Step 2 — Where does $app run?

- Reuses the `SelectableCard` pair from `ConfigurationPage`
  (`Target.thisDevice` / `Target.otherDevice`) with the design's additions: icon,
  description, and an "→ enables the Local/Network method" explainer strip per card
  (new strings).
- Same settings write as today. Note at the bottom: changeable later in Connection
  Settings.

### Step 3 — Controller (phases: permission → scanning → list → connected)

- **Permission rationale** screen (design copy: find nearby controllers / keep you
  posted / never used for location) fronting the existing permission machinery
  (`core.permissions.getScanRequirements()` → `openPermissionSheet`). "Not now" opens
  the permission-denied sheet (below).
- **Scanning:** `SmoothWifiAnimation` + `core.connection.performScanning()` /
  `isScanning`. Design's radar is realized by the existing animation widget.
- **List:** devices appear as they are discovered and **auto-connect** (unchanged
  behaviour). Compact onboarding device row: icon, name, status (connecting spinner →
  Connected badge), "Setup needed" badge for devices with extra steps. Not the full
  `showInformation` card.
- **Sub-flows** trigger when such a device connects: Zwift Click V2 → existing
  `UnlockPage` (bottom drawer); SRAM AXS → existing `SramGuidedSheet`. Their internal
  copy is refreshed from the design where better (see Strings).
- **Empty state** ("no controllers found"): wake the device / disconnect it elsewhere /
  get closer + Scan again + "Set this up later" (advances).
- **Connected:** success badge + connected device row + note that buttons are already
  mapped for $app. Footer becomes the **button hint**: "Press a button on your
  controller to continue … or tap here" — advances on a real button press from the
  connected controller, tap as fallback. (Deliberate deviation: generic "press a
  button" instead of the mock's "Press Shift Up", since mappings vary per device.
  Exact event source to be determined during planning — whatever existing signal
  fires on button input, e.g. the activity-log/action path; if none is cleanly
  reachable, ship tap-only without blocking.)

### Step 4 — Virtual shifting (optional, Skip in header)

- Pitch: "Let BikeControl handle Virtual Shifting" + three benefits (own gear ratios /
  consistent resistance / works where the app doesn't) + link to
  bikecontrol.app/virtual-shifting.
- **Nearby smart trainers** list from the existing scan (FTMS + WiFi discovery);
  tap-to-pair via the existing `connectDevice` path, with connecting → connected
  states.
- Skip framing: footer ghost button "Let $app handle Virtual Shifting" — the single
  place the app's own shifting is mentioned.
- Pro gating unchanged: virtual shifting remains governed by
  `isProEnabledForCurrentDevice` and its trial; **no** `OrDidPurchaseOld`
  grandfathering. Onboarding only surfaces the existing trial.

### Step 5 — Connect to $app

- **Connection methods** as selectable tiles: Network (recommended, on by default),
  Bluetooth (only for apps that accept it; "Best on iOS" badge), Local (macOS ·
  Windows · Android; disabled with a reason on iOS). Availability, platform gating and
  settings writes reuse the existing connection-method logic behind
  `lib/widgets/apps/*_tile.dart` / `TrainerPage`; pre-selection derives from steps 1–2.
- **"Then in $app" card:** numbered in-app steps per official app, setup screenshots
  hotlinked from bikecontrol.app (must degrade gracefully offline — hide on load
  failure), and a link to the app's partnership guide. Content lives in a small
  per-app data table (steps/screenshot URLs/guide URL) using the design's inventory;
  generic two-step fallback for apps without a guide.
- **Bridge card** (only if a trainer was paired in step 4): "Pair BikeControl as your
  trainer" — pick the "$trainer - BikeControl" entry in the app, not the raw trainer;
  shows the Live tile, the power/resistance/cadence slots, and the warning that pairing
  the trainer directly bypasses BikeControl's gears.
- Footer: "Finish setup", disabled when no method is enabled.

### Step 6 — Ready + test mode

- Success animation (ring burst + pop-in check) built from the shared primitives in
  `lib/widgets/guided_operation_sheet.dart` (`StageBadge` etc.).
- Summary rows reflecting the run's actual state: controller (Connected), $app
  (method), bridged trainer — anything skipped simply doesn't appear.
- **Test mode** warning card: ride now and verify; daily command budget, plus
  20 min/day virtual shifting when a trainer is bridged — built on existing trial
  strings, reworded per design where better.
- Footer: primary "See Pro & Base options" → existing `SubscriptionPage`
  (end drawer, real IAP); ghost "Done — start riding". Both set
  `onboarding_completed` and leave the flow (paywall path sets it too — the flow is
  complete regardless of purchase).

### Help (every step)

- Mobile: Help pill in the header. Desktop: "Help & Support" at the rail bottom.
- Opens a sheet with a **contextual answer for the current step** (design's per-step
  Q&A copy) above four standing channels: setup guides (bikecontrol.app), community
  groups, contact support (existing in-app support composer where available, else
  mail), GitHub issue tracker.

### Permission-denied sheet

"BikeControl can't find devices" — explains no-permission consequence, offers
**Continue anyway** (advances to step 4) and **Allow Bluetooth** (retries).

## State & data flow

- The wizard holds UI state only; **each step commits through the same settings paths
  the current UI uses** (app select, `Target`, connection methods) the moment the user
  advances. No parallel "wizard result" object. A half-finished run therefore leaves a
  valid configuration.
- Live data via existing notifiers: `core.connection.isScanning`, connection change
  signals for the device list, button events for the hint footer. No new BLE plumbing.
- Sub-flow sheets are overlay routes, not steps — cancel/back returns to the hosting
  step.

## Error handling

Every failure path lands in a designed state; every catch forwards
`recordError(e, s, context: 'onboarding …')` (never swallowed):

- Bluetooth permission declined → permission-denied sheet with Continue anyway.
- Empty scan → tips + rescan (design copy).
- SRAM bond/authorize errors → handled inside `SramGuidedSheet` as today.
- Click V2 unlock issues → handled inside `UnlockPage` as today.
- Trainer pairing failure → back to trainer list + toast.
- Setup screenshots failing to load (offline) → hidden, no broken images.
- Skipped controller/trainer → steps 5–6 adapt (no bridge card, no summary row).

## Strings / l10n

- All new copy in `lib/i10n/intl_en.arb` **only** (Localazy translates); regenerate
  accessors with `flutter pub global run intl_utils:generate`; never hand-edit
  `lib/gen/l10n.dart`.
- Use the design's wording for all new strings (key prefix `onboarding*`).
- Where the design improved an existing string (Click V2 pros/cons vs
  `clickV2Onboarding_*`, SRAM intro, scan-empty guidance), update the English source
  in place so the regular UI improves too.

## Testing

- **Snapshot tests** per the `test/sram_states_snapshot_test.dart` pattern: step bodies
  are pure functions of explicit state; render every step/phase state (the design kit's
  "Jump to state" list) at both a mobile (<800) and desktop (≥800) width.
- **Widget tests** for flow logic: advance/back/skip transitions, footer
  enable/disable, pref gating (shows on fresh install; not after completion; hidden in
  `screenshotMode`), re-run entry.
- No l10n-literal assertions (`expect(AppLocalizations.current.x, 'literal')`).

## Out of scope

- Tap-to-pick device connection (auto-connect stays).
- A new Base/Pro paywall UI (existing `SubscriptionPage` is used).
- Changing the regular settings pages (app dropdown, connection settings) beyond
  shared string improvements.
- Bundling setup screenshots into the app (they stay hotlinked).
- The design kit's phone-frame/status-bar chrome (design-review scaffolding only).

## Key reuse map

| Design element | Existing code |
| --- | --- |
| Scan animation | `lib/widgets/ui/wifi_animation.dart` (`SmoothWifiAnimation`) |
| Scan/permission logic | `lib/widgets/scan.dart`, `core.permissions`, `openPermissionSheet` |
| SRAM sub-flow | `lib/bluetooth/devices/sram/sram_setup_sheet.dart` (`SramGuidedSheet`) |
| Click V2 sub-flow | `lib/pages/unlock.dart` (`UnlockPage`) |
| Where-it-runs cards | `lib/pages/configuration.dart` `SelectableCard`s (`Target`) |
| App inventory | `lib/utils/keymap/apps/supported_app.dart` |
| Connection methods | `lib/widgets/apps/*_tile.dart`, `lib/pages/trainer.dart` |
| Badges/checklist/pop-in | `lib/widgets/guided_operation_sheet.dart` |
| Paywall | `lib/pages/subscription.dart` (`SubscriptionPage`) |
| One-time gating pattern | `virtual_shifting_intro_page.dart` + `settings.dart` prefs |
