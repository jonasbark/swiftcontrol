# Battery-Saver Reconnect Cooldown Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** After the battery-saver inactivity disconnect, lift the auto-reconnect suppression 90 seconds later so a rediscovered (woken) controller reconnects automatically again.

**Architecture:** `Connection._onInactivityTimeout` already adds disconnected controller ids to `_suppressedAutoReconnect`. Add a single `Timer` per timeout batch that, after `inactivityReconnectCooldown` (90 s, mutable test seam), removes each id from `_suppressedAutoReconnect` **and** purges its `_lastScanResult` entry — the stale dedup entry is what blocks rediscovery forever today (zerkms's bug). No change to `InactivityDisconnector` (stays pure timing logic).

**Tech Stack:** Flutter/Dart, fake-BLE integration harness (`test/integration/`), intl_utils for i18n.

**Spec:** `docs/superpowers/specs/2026-07-03-battery-saver-reconnect-cooldown-design.md`

## Global Constraints

- Cooldown default: `Duration(seconds: 90)`.
- Branch: `6.3`. Jonas may commit in parallel — `git add` only the exact files listed, never `git add -A`.
- All existing tests must keep passing: `flutter test test/integration/controller_connection_test.dart` and `flutter test test/inactivity_disconnector_test.dart`.

---

### Task 1: Reconnect cooldown in Connection

**Files:**
- Modify: `lib/bluetooth/connection.dart` (field near line 97, logic in `_onInactivityTimeout` near line 803, comment updates at lines ~91-97, ~490-492, ~808-811)
- Test: `test/integration/controller_connection_test.dart` (append to the same group as the existing battery-saver tests, after line 288)

**Interfaces:**
- Consumes: existing `debugTriggerInactivityTimeout()`, `env.ble.updateScanResult(BleDevice)`, `buildZwiftClick()`, `autoRespondToZwiftHandshake(...)`, `IntegrationEnv.waitFor(...)` — all already used by neighboring tests in the same file.
- Produces: `Duration Connection.inactivityReconnectCooldown` (public mutable field, default 90 s) — used by Task 1's tests; no other task depends on it.

- [ ] **Step 1: Write the two failing tests**

Append inside the same `group` as the existing test `'the battery-saver Reconnect action clears the suppression and reconnects'` (i.e. before the group's closing `});` at line 289):

```dart
    test('after the reconnect cooldown a rediscovered controller auto-reconnects', () async {
      final click = buildZwiftClick();
      autoRespondToZwiftHandshake(env.ble, click);
      env.ble.addPeripheral(click);

      await core.connection.performScanning();
      final device = await waitForDevice<ZwiftClick>();
      await IntegrationEnv.waitFor(() => device.isConnected, description: 'connect');

      // Shrink the cooldown so the test doesn't wait 90 real seconds.
      // core.connection is shared across the file — restore the default so
      // later tests keep the real suppression behavior.
      core.connection.inactivityReconnectCooldown = const Duration(milliseconds: 300);
      addTearDown(() => core.connection.inactivityReconnectCooldown = const Duration(seconds: 90));
      core.connection.debugTriggerInactivityTimeout();
      await IntegrationEnv.waitFor(
        () => core.connection.devices.whereType<ZwiftClick>().isEmpty,
        description: 'controller removed after inactivity disconnect',
      );

      // Inside the cooldown window the suppression still holds.
      core.connection.addDevices([BluetoothDevice.fromScanResult(click.scanResult)!]);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(
        core.connection.devices.whereType<ZwiftClick>(),
        isEmpty,
        reason: 'controller reconnected during the cooldown window',
      );

      // Once the cooldown elapsed, rediscovery must reconnect normally again.
      await Future<void>.delayed(const Duration(milliseconds: 400));
      core.connection.addDevices([BluetoothDevice.fromScanResult(click.scanResult)!]);
      await IntegrationEnv.waitFor(
        () => core.connection.devices.whereType<ZwiftClick>().any((d) => d.isConnected),
        description: 'controller reconnects after the cooldown',
      );
    });

    test('a woken controller reconnects via the scan path after the cooldown', () async {
      final click = buildZwiftClick();
      autoRespondToZwiftHandshake(env.ble, click);
      env.ble.addPeripheral(click);

      await core.connection.performScanning();
      final device = await waitForDevice<ZwiftClick>();
      await IntegrationEnv.waitFor(() => device.isConnected, description: 'connect');

      core.connection.inactivityReconnectCooldown = const Duration(milliseconds: 300);
      addTearDown(() => core.connection.inactivityReconnectCooldown = const Duration(seconds: 90));
      core.connection.debugTriggerInactivityTimeout();
      await IntegrationEnv.waitFor(
        () => core.connection.devices.whereType<ZwiftClick>().isEmpty,
        description: 'controller removed after inactivity disconnect',
      );

      // Right after the disconnect the controller is still awake and
      // advertises: the advertisement lands in the _lastScanResult dedup list
      // while the suppression drops the device. This stale entry used to block
      // every later advertisement from ever reaching addDevices (issue #329,
      // zerkms's repro: stuck "scanning" until an app restart).
      env.ble.updateScanResult(click.scanResult);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(
        core.connection.devices.whereType<ZwiftClick>(),
        isEmpty,
        reason: 'controller reconnected during the cooldown window',
      );

      // The controller sleeps, the cooldown elapses, the rider wakes it with a
      // button press -> a fresh advertisement must reconnect it via the scan
      // path (no explicit Reconnect tap, no app restart).
      await Future<void>.delayed(const Duration(milliseconds: 400));
      env.ble.updateScanResult(click.scanResult);
      await IntegrationEnv.waitFor(
        () => core.connection.devices.whereType<ZwiftClick>().any((d) => d.isConnected),
        description: 'controller reconnects via scan after the cooldown',
      );
    });
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `flutter test test/integration/controller_connection_test.dart`
Expected: compile error — `inactivityReconnectCooldown` is not defined on `Connection`. (After Step 3's field exists but before the timer logic, the failure mode is the `waitFor` timeout on 'controller reconnects after the cooldown'.)

- [ ] **Step 3: Implement the cooldown**

In `lib/bluetooth/connection.dart`:

3a. Extend the `_suppressedAutoReconnect` doc comment (lines 91-97) and add the new field directly below the set:

```dart
  /// BLE ids of controllers disconnected by the inactivity battery saver. They
  /// are deliberately NOT added to the ignore list (so the user can reconnect),
  /// but must not be auto-reconnected when rediscovered (via scan results,
  /// getSystemDevices or the disconnect listener's performScanning) — otherwise
  /// they reconnect right after the battery-saver disconnect. Cleared on an
  /// explicit reconnect, a successful (re)connect, or automatically once
  /// [inactivityReconnectCooldown] has elapsed — after that a rediscovered
  /// (woken) controller auto-reconnects normally again.
  final _suppressedAutoReconnect = <String>{};

  /// How long after the battery-saver disconnect a controller stays suppressed.
  /// Long enough for the controller to stop advertising and fall asleep;
  /// afterwards any advertisement means the rider woke it and wants it back.
  /// Mutable as a test seam (the integration tests shrink it to milliseconds).
  Duration inactivityReconnectCooldown = const Duration(seconds: 90);
```

3b. In `_onInactivityTimeout` (line ~803), update the suppression comment and start the cooldown timer after the disconnect loop:

```dart
    for (final device in controllers) {
      // Suppress auto-reconnect so the rediscovery that follows the disconnect
      // doesn't immediately bring the controller back (the whole point is to
      // let its battery rest). Lifted by the Reconnect action below or by the
      // cooldown timer once the controller had time to fall asleep.
      _suppressedAutoReconnect.add(device.device.deviceId);
      unawaited(
        disconnect(device, forget: true, persistForget: false).catchError((Object error, StackTrace stackTrace) {
          _actionStreams.add(
            LogNotification('Failed to disconnect ${device.toString()} after inactivity timeout: $error\n$stackTrace'),
          );
        }),
      );
    }

    // Lift the suppression once the controller had time to power down. The
    // stale _lastScanResult entry must go too: the controller's last
    // advertisement right after the disconnect re-entered the dedup list, and
    // it would block every future advertisement from reaching addDevices —
    // leaving a woken controller unconnectable until an app restart.
    final suppressedIds = controllers.map((d) => d.device.deviceId).toList();
    Timer(inactivityReconnectCooldown, () {
      for (final id in suppressedIds) {
        _suppressedAutoReconnect.remove(id);
        _lastScanResult.removeWhere((d) => d.deviceId == id);
      }
    });
```

3c. Update the stale comment in `addDevices` (lines 490-491):

```dart
        // A controller the battery saver disconnected must not silently
        // reconnect when rediscovered until the reconnect cooldown has passed
        // or the user explicitly reconnects it.
        if (_suppressedAutoReconnect.contains(device.device.deviceId)) {
          return false;
        }
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `flutter test test/integration/controller_connection_test.dart`
Expected: all tests in the file PASS, including the two existing battery-saver tests (their suppression assertions sample well inside the default 90 s cooldown, so they are unaffected).

Also run: `flutter test test/inactivity_disconnector_test.dart`
Expected: PASS (file untouched — guards against accidental edits).

- [ ] **Step 5: Commit**

```bash
git add lib/bluetooth/connection.dart test/integration/controller_connection_test.dart
git commit -m "fix(battery-saver): allow auto-reconnect 90s after the inactivity disconnect (#329)"
```

---

### Task 2: Tell the rider they can just wake the controller

**Files:**
- Modify: `lib/i10n/intl_en.arb:186`, `lib/i10n/intl_de.arb:4`, `lib/i10n/intl_es.arb:4`, `lib/i10n/intl_fr.arb:4`, `lib/i10n/intl_it.arb:4`, `lib/i10n/intl_pl.arb:4`

**Interfaces:**
- Consumes: the `controllersDisconnectedInactivity` key already used by `_onInactivityTimeout` for both the in-app alert and the OS notification — no Dart code change needed.
- Produces: updated copy in all six locales; regenerated `lib/gen/` localizations (not committed — `lib/gen/` is gitignored/generated).

- [ ] **Step 1: Update the six arb values**

Replace only the value of `"controllersDisconnectedInactivity"` in each file (placeholders metadata in `intl_en.arb` stays unchanged):

```json
// intl_en.arb
"controllersDisconnectedInactivity": "Controllers disconnected after {minutes} minutes of inactivity to save battery. Turn a controller back on to reconnect it.",

// intl_de.arb
"controllersDisconnectedInactivity": "Controller nach {minutes} Minuten Inaktivität getrennt, um Akku zu sparen. Schalte einen Controller wieder ein, um ihn neu zu verbinden.",

// intl_es.arb
"controllersDisconnectedInactivity": "Mandos desconectados tras {minutes} minutos de inactividad para ahorrar batería. Vuelve a encender un mando para reconectarlo.",

// intl_fr.arb
"controllersDisconnectedInactivity": "Manettes déconnectées après {minutes} minutes d'inactivité pour économiser la batterie. Rallumez une manette pour la reconnecter.",

// intl_it.arb
"controllersDisconnectedInactivity": "Controller disconnessi dopo {minutes} minuti di inattività per risparmiare batteria. Riaccendi un controller per riconnetterlo.",

// intl_pl.arb
"controllersDisconnectedInactivity": "Kontrolery rozłączone po {minutes} minutach bezczynności, aby oszczędzać baterię. Włącz ponownie kontroler, aby go połączyć.",
```

- [ ] **Step 2: Regenerate localizations and verify**

Run: `dart run intl_utils:generate`
Expected: exits 0, regenerates `lib/gen/`.

Run: `flutter analyze lib/bluetooth/connection.dart`
Expected: `No issues found!`

Run: `flutter test test/integration/controller_connection_test.dart`
Expected: PASS (no test asserts on the notification copy).

- [ ] **Step 3: Commit**

```bash
git add lib/i10n/intl_en.arb lib/i10n/intl_de.arb lib/i10n/intl_es.arb lib/i10n/intl_fr.arb lib/i10n/intl_it.arb lib/i10n/intl_pl.arb
git commit -m "feat(battery-saver): mention waking the controller in the disconnect notification (#329)"
```
