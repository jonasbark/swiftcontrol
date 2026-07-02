# Controller & Accessory Emulation (Debug)

**Date:** 2026-07-02
**Status:** Implemented

## Problem

Verifying a controller or accessory today requires the physical hardware. The only
shortcut is the debug-only "Continue" menu item (`lib/widgets/menu.dart`), which
injects one hard-coded fake `ZwiftClickV2` via `core.connection.addDevices()` and
gets hand-edited for whatever device is being looked at. It only exercises the
device-list UI: the fake device never connects, its buttons can't be pressed, and
every other device class goes unverified.

The goal: emulate **any** supported controller or accessory from inside the app so
each one can be verified end-to-end — detection, connect flow, device page UI,
button → keymap → action pipeline, and accessory write behavior — without owning
the hardware.

## Key insight

The integration-test harness already contains the hard part:

- `test/integration/harness/fake_ble_platform.dart` — `FakeUniversalBlePlatform`,
  a complete in-memory `UniversalBlePlatform`: peripherals with GATT tables,
  canned read values, write logs, an `onWrite` scripting hook, notification
  injection (`notify`), and connection-drop simulation.
- `test/integration/harness/fake_peripherals.dart` — faithful peripheral builders
  for Zwift Click, Zwift Ride, Shimano Di2, and an FTMS trainer, plus the Zwift
  RideOn handshake auto-responder and button-notification encoders.

Full-fidelity emulation is therefore a matter of promoting this harness into
`lib/` and putting a picker UI in front of it — not building an emulator from
scratch.

## Approach (chosen: A)

Promote the fake BLE harness into the app. Emulated peripherals are registered
with a fake platform; a routing platform lets them coexist with real hardware.
Emulated devices flow through the **real** production code path:
`fromScanResult` detection → connection queue → `connect()` → service discovery →
handshake → firmware/battery reads → notification subscriptions →
`processCharacteristic` decoding → `handleButtonsClicked` → keymap → actions.

Rejected alternatives:

- **B. Flag-based bypass in `BluetoothDevice`** — `if (isEmulated)` scattered
  through production code; skips detection/connect/decode; accessories that
  write to BLE at runtime (Headwind, Climb) would throw.
- **C. Generic `EmulatedController` class** — verifies nothing about the real
  device classes, which is the point of the feature.

## Components

### 1. Shared emulation harness (`lib/bluetooth/emulation/`)

Move and rename:

- `test/integration/harness/fake_ble_platform.dart` →
  `lib/bluetooth/emulation/emulated_ble_platform.dart`
- `test/integration/harness/fake_peripherals.dart` →
  `lib/bluetooth/emulation/emulated_peripherals.dart`

Integration tests import from `lib/` afterwards; no behavior change. Every
peripheral builder written for the emulator is usable in tests and vice versa —
one source of truth.

### 2. Routing platform (`RoutingBlePlatform`)

`RoutingBlePlatform extends UniversalBlePlatform`, owning the real platform and
the fake one:

- Dispatches per-call by device ID: `emulated:` prefix → fake, otherwise real.
- Forwards both platforms' event callbacks (scan results, connection changes,
  characteristic updates) to its own — the instance `Connection` registered on.
- `startScan`/`stopScan` fan out to both; the fake emits its registered
  peripherals immediately.
- Installed via `UniversalBle.setInstance()` **before**
  `Connection.initialize()` (callbacks live on the instance), **debug builds
  only** (`kDebugMode`). Pure pass-through while no emulated peripheral is
  registered. Could later ship behind a hidden setting for beta testers.

### 3. Device catalog (emulation profiles)

A registry mapping each supported device to an emulation profile:

- display name + category (controller / steering / incline / accessory)
- `FakePeripheral Function()` builder (GATT layout, advertised services,
  manufacturer data, canned reads, scripted handshake)
- input descriptor: which controls the Emulation card renders (buttons with
  their notification encoders, steering slider, write-log view)

Initial coverage (GATT + payload bytes lifted from each device's existing unit
test):

| Family | Devices |
|---|---|
| Zwift | Click (exists), Ride (exists), ClickV2 left/right, Play |
| Elite | Sterzo, Square, Rizer |
| Wahoo | Kickr Bike Shift, Climb, Headwind |
| Others | Shimano Di2 (exists), Cycplus BC2, ThinkRider VS200, SRAM AXS, OpenBikeControl |

Fallback: devices whose notification payloads are impractical to encode drive
`device.handleButtonsClicked()` directly — still exercises the
button → keymap → action pipeline, skipping only the byte decoder. The profile
records which mode each device uses.

### 4. "Emulate device…" menu

The debug menu's "Continue" item is replaced by "Emulate device…", listing the
catalog (grouped by category). Picking an entry registers the peripheral with
the fake platform; the normal scan/detect/connect flow does the rest.

- Emulated devices are **not persisted** across restarts.
- Removal uses the existing forget/disconnect UI; forgetting also unregisters
  the peripheral from the fake platform.

### 5. Emulation card (input surface)

The device page (`ControllerSettingsPage`/`DevicePage`) shows an "Emulation"
card only for emulated devices (device ID prefix check):

- **Button controllers:** press-and-hold buttons injecting encoded
  notifications via `ble.notify(...)`. Press sends the pressed frame,
  release the released frame — so the app's real long-press / double-click /
  repeat timing logic runs exactly as with hardware.
- **Steering (Sterzo, Rizer):** an angle slider emitting angle notifications.
- **Accessory sinks (Climb, Rizer incline, Headwind):** a live decoded log of
  what the app **wrote** to the peripheral (target incline, fan speed) — the
  verification direction for these devices. Rizer shows both slider and log.
- **Common controls:** battery-level and RSSI tweakers (re-notify / update scan
  result) and a "drop connection" button (`dropConnection`) to verify
  disconnect/reconnect UX.

## Data flow

```
Emulate menu → catalog profile → FakePeripheral registered on fake platform
  → scan result emitted → BluetoothDevice.fromScanResult (real detection)
  → Connection queue → device.connect() (real flow: MTU, services, device info,
    battery, handleServices, scripted handshake)
  → Emulation card input → ble.notify(encoded bytes)
  → processCharacteristic (real decoder) → handleButtonsClicked
  → keymap → in-game action
Accessory direction: incline/fan pipeline → UniversalBle.write → fake platform
  → write log decoded on Emulation card
```

## Error handling

Inherited from the harness: the fake platform behaves as a well-behaved
peripheral. Failure modes are injectable for UX verification — drop connection,
missing characteristic (omit from GATT in a builder variant), empty reads. No
new error paths in production code; the routing platform rethrows real-platform
errors unchanged.

## Testing

- The moved harness keeps its existing integration-test consumers as regression
  coverage for the move itself.
- Each new peripheral builder gets a smoke test: scan → detect (asserts the
  expected device class) → connect → inject input → assert the expected action
  fired. These double as automated verification of controllers there's no
  hardware for.
- A test covers the routing platform's dispatch and event-forwarding logic.

## Out of scope

- **Trainers / `ProxyDevice`** — own emulator infrastructure already exists;
  `buildFtmsTrainer` remains available if wanted later.
- **Gamepad / HID / Gyroscope** — non-BLE input paths; gyroscope already has a
  toggle in the UI.
- **Zwift encrypted-mode fidelity** — the harness scripts the unencrypted
  handshake path, same as the existing integration tests.
- **Release builds** — menu entry and platform installation are `kDebugMode`
  only for now.
