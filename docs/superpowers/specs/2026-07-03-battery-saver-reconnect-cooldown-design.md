# Battery-Saver Reconnect Cooldown

**Date:** 2026-07-03
**Issue:** [#329](https://github.com/OpenBikeControl/bikecontrol/issues/329) — follow-up to the inactivity battery-saver disconnect
**Resolves:** [comment 4833308986](https://github.com/OpenBikeControl/bikecontrol/issues/329#issuecomment-4833308986) and zerkms's repro (comment 4872049888)

## Problem

The inactivity battery saver disconnects idle BLE controllers and suppresses
auto-reconnect so they can power down. But the suppression is permanent: once a
controller lands in `Connection._suppressedAutoReconnect`, only the alert's
Reconnect button, an explicit reconnect from the device picker, or
`disconnectAll` clears it. A rider who turns the controller back on mid-session
(fabien88fr14's heat-training case) cannot get it reconnected without finding
the alert or restarting the app.

There is a second, hidden layer that makes it worse (zerkms's repro — app stuck
"scanning" forever even after waking the controller and even after an explicit
rescan):

- The scan handler (`connection.dart`, `UniversalBle.onScanResult`) dedupes on
  `_lastScanResult` — a device already in that list never reaches
  `addDevices` again.
- The battery saver disconnects with `forget: true`, and `disconnect()` only
  purges the device's `_lastScanResult` entry when `!forget`.
- The controller keeps advertising briefly after the disconnect, so its first
  post-disconnect advertisement re-enters `_lastScanResult` (then gets dropped
  by the suppression check in `addDevices`). Every later advertisement — e.g.
  when the rider wakes the device 30 minutes later — is deduped upstream and
  never reaches `addDevices` at all.
- Only an app restart clears `_lastScanResult`, which is why restarting
  reconnects immediately.

So clearing the suppression flag alone would not fix reconnection; the stale
`_lastScanResult` entry must be purged too.

## Decision

Fixed reconnect cooldown of **90 seconds**, per Jonas's proposal (issue reply:
"a timer to allow reconnection after e.g. one minute of the last disconnect";
90 s chosen for headroom so controllers that advertise a while after the
disconnect still get to sleep).

When `_onInactivityTimeout` suppresses the disconnected controllers, it also
starts a single `Timer` for the batch. When the timer fires, for each
suppressed device id:

1. remove it from `_suppressedAutoReconnect`, and
2. purge its entry from `_lastScanResult`.

After that, the next advertisement — whether the controller never slept, or the
rider wakes it hours later with a button press — flows through the normal
`onScanResult` → `addDevices` → connection-queue path and reconnects with the
usual "Connecting…"/"Connection succeeded" notifications. No new state machine;
the cooldown simply time-boxes the suppression.

### Alternatives considered

- **Absence-based wake detection** (clear suppression once the device has not
  advertised for ~30 s, i.e. actually asleep): battery-optimal, but needs
  per-device advertisement timestamps and is fragile under Android's
  duplicate-advertisement scan throttling, which fakes "silence".
- **Expiry timestamp checked in the scan path**: store the suppression time and
  treat old entries as expired on the next sighting. Messier — the
  `_lastScanResult` dedup sits upstream of the suppression check, so it needs a
  bypass there anyway.

Trade-off accepted: a controller that keeps advertising longer than 90 s
reconnects and battery saving is lost for that device. Most supported
controllers stop advertising and sleep well within the window.

## Changes

### `lib/bluetooth/connection.dart`

- New constant + test seam on `Connection`:
  `Duration inactivityReconnectCooldown = const Duration(seconds: 90);`
  (`@visibleForTesting` setter or a plain mutable field, matching the existing
  `debugTriggerInactivityTimeout` seam style).
- `_onInactivityTimeout`: after the disconnect loop, capture the suppressed
  device ids and start `Timer(inactivityReconnectCooldown, ...)` that removes
  each id from `_suppressedAutoReconnect` and purges it from `_lastScanResult`.
- Idempotency: if the user hit Reconnect (or `disconnectAll` ran) before the
  timer fires, the removals are no-ops. A `_lastScanResult` purge for a
  meanwhile-reconnected device is harmless — the reprocessed advertisement is
  filtered by `devices.contains(...)` in `addDevices`.
- No change to `InactivityDisconnector` — it stays pure timing logic; the
  cooldown is Connection-side because the suppression set lives there.

### i18n (`lib/i10n/intl_*.arb`, 6 locales)

Extend `controllersDisconnectedInactivity` so the alert and the OS push
notification tell the rider the new behavior, e.g. (en):

> "Controllers disconnected after {minutes} minutes of inactivity to save
> battery. Turn the controller back on to reconnect."

All six locales updated in the same shape.

## Testing

Integration tests in `test/integration/controller_connection_test.dart`,
following the existing battery-saver tests:

1. **Cooldown restores auto-reconnect:** connect a Zwift Click, trigger
   `debugTriggerInactivityTimeout()`, feed a fresh advertisement — must NOT
   reconnect (existing behavior). Set `inactivityReconnectCooldown` to
   milliseconds, wait it out, feed an advertisement again — must reconnect.
2. **Stale scan-dedup entry is purged:** same flow, but deliver the
   advertisement *during* the suppression window first (so `_lastScanResult`
   holds the stale entry — zerkms's exact repro), then after the cooldown —
   must still reconnect.
3. Existing tests ("not auto-reconnected on rediscovery", "Reconnect action
   clears the suppression") keep passing — with the cooldown left at a value
   long enough not to interfere.
