# Controller & Accessory Emulation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Emulate any supported BLE controller or accessory from inside the app (debug builds) so each device can be verified end-to-end without hardware.

**Architecture:** Promote the integration-test fake-BLE harness (`FakeUniversalBlePlatform` + peripheral builders) into `lib/bluetooth/emulation/`. A `RoutingBlePlatform` installed via `UniversalBle.setInstance()` in debug builds dispatches per device ID between the real platform and the fake one, so emulated peripherals coexist with real hardware and flow through the real detection → connect → decode → keymap pipeline. An `EmulationManager` (`core.emulation`) owns emulation profiles/sessions; a debug menu adds devices; an Emulation card on `ControllerSettingsPage` injects protocol frames and shows decoded app→device writes.

**Tech Stack:** Flutter/Dart, universal_ble (jonasbark fork), shadcn_flutter, prop package (Zwift protobufs), flutter_test.

**Spec:** `docs/superpowers/specs/2026-07-02-controller-emulation-design.md`

## Global Constraints

- All new UI and the platform swap are `kDebugMode`-only. `EmulationManager` exists in release but is never attached (inert).
- Emulated device IDs are prefixed `emulated:` and are stable per profile (re-adding is idempotent).
- Moved harness classes keep their names (`FakeUniversalBlePlatform`, `FakePeripheral`, `buildZwiftClick`, `buildZwiftRide`, `buildShimanoDi2`, `buildFtmsTrainer`, `autoRespondToZwiftHandshake`, `zwiftClickNotification`, `zwiftRideNotification`, `zwiftBatteryNotification`) — only file paths change.
- Zwift Ride-protocol frames MUST use the app-side `RideButtonMask` from `lib/bluetooth/devices/zwift/zwift_ride.dart` (`import ... show RideButtonMask`, `import 'package:prop/prop.dart' hide RideButtonMask`) — the prop enum has different values.
- Never modify anything under `prop/` or `prop_public/` (submodules) or the universal_ble fork.
- UUIDs in fake GATT tables are lowercase (use the `lcUuid` helper or lowercase literals).
- Test command: `flutter test <path>`. Full check: `flutter analyze` must stay clean.
- Commit after every task with a conventional-commit message.

## File Structure

Created:
- `lib/bluetooth/emulation/emulated_ble_platform.dart` — moved `FakeUniversalBlePlatform` + `FakePeripheral` (Task 1), + `removePeripheral` (Task 3)
- `lib/bluetooth/emulation/emulated_peripherals.dart` — moved peripheral builders/encoders; helpers made public (Task 1)
- `lib/bluetooth/emulation/real_ble_platform.dart` + `real_ble_platform_stub.dart` + `real_ble_platform_io.dart` + `real_ble_platform_web.dart` — factory for the platform universal_ble would have picked (Task 2)
- `lib/bluetooth/emulation/routing_ble_platform.dart` — `RoutingBlePlatform` (Task 2)
- `lib/bluetooth/emulation/emulation_profile.dart` — `EmulationProfile`, `EmulationCategory`, `EmulatedInput`/`EmulatedButton`/`EmulatedAction` (Task 3)
- `lib/bluetooth/emulation/emulation_manager.dart` — `EmulationManager`, `EmulationSession` (Task 3)
- `lib/bluetooth/emulation/profiles/zwift_profiles.dart` (Tasks 3, 7), `elite_profiles.dart` (Task 8), `wahoo_profiles.dart` (Task 9), `misc_profiles.dart` (Task 10), `all_profiles.dart` (Task 3, grows)
- `lib/widgets/emulation_card.dart` — Emulation card widget (Task 6)

Modified:
- `test/integration/harness/test_env.dart`, `test/integration/controller_connection_test.dart`, `test/integration/controller_button_chain_test.dart`, `test/integration/virtual_shifting_connection_logic_test.dart`, `test/bluetooth/front_shift_combo_test.dart` — import path updates (Task 1)
- `lib/utils/core.dart` — `emulation` field (Task 3)
- `lib/main.dart` — debug platform install (Task 3)
- `lib/bluetooth/connection.dart` — forget hook (Task 4)
- `lib/widgets/menu.dart` — "Emulate device" submenu replaces "Continue" (Task 5)
- `lib/pages/controller_settings.dart` — Emulation card section (Task 6)

Tests created:
- `test/bluetooth/emulation/routing_ble_platform_test.dart` (Task 2)
- `test/bluetooth/emulation/emulation_manager_test.dart` (Task 3)
- `test/integration/emulation_forget_test.dart` (Task 4)
- `test/widgets/emulation_card_test.dart` (Task 6)
- `test/integration/emulation_zwift_profiles_test.dart` (Task 7)
- `test/integration/emulation_elite_profiles_test.dart` (Task 8)
- `test/integration/emulation_wahoo_profiles_test.dart` (Task 9)
- `test/integration/emulation_misc_profiles_test.dart` (Task 10)

---

### Task 1: Move the fake-BLE harness into lib

The integration-test harness becomes shared production (debug) code. Class names stay; file names change; three private helpers in the peripherals file become public so later profile files can reuse them.

**Files:**
- Create (via git mv): `lib/bluetooth/emulation/emulated_ble_platform.dart` (from `test/integration/harness/fake_ble_platform.dart`)
- Create (via git mv): `lib/bluetooth/emulation/emulated_peripherals.dart` (from `test/integration/harness/fake_peripherals.dart`)
- Modify: `test/integration/harness/test_env.dart:18`
- Modify: `test/integration/controller_connection_test.dart:14-15`
- Modify: `test/integration/controller_button_chain_test.dart:13-14`
- Modify: `test/integration/virtual_shifting_connection_logic_test.dart:17-18`
- Modify: `test/bluetooth/front_shift_combo_test.dart:12-13`

**Interfaces:**
- Consumes: nothing new.
- Produces: `package:bike_control/bluetooth/emulation/emulated_ble_platform.dart` exporting `FakeUniversalBlePlatform` and `FakePeripheral` (unchanged APIs); `package:bike_control/bluetooth/emulation/emulated_peripherals.dart` exporting the existing builders plus now-public helpers with these exact signatures:
  - `String lcUuid(String uuid)` (was `_lc`)
  - `BleCharacteristic bleChar(String uuid, List<CharacteristicProperty> properties)` (was `_char`)
  - `List<BleService> deviceInfoServices(FakePeripheral peripheral, {String firmware = '1.0.0', int battery = 88})` (was `_deviceInfoServices`)

- [ ] **Step 1: Move the files**

```bash
mkdir -p lib/bluetooth/emulation
git mv test/integration/harness/fake_ble_platform.dart lib/bluetooth/emulation/emulated_ble_platform.dart
git mv test/integration/harness/fake_peripherals.dart lib/bluetooth/emulation/emulated_peripherals.dart
```

- [ ] **Step 2: Fix the internal import and publicize helpers**

In `lib/bluetooth/emulation/emulated_peripherals.dart`:
- Change `import 'fake_ble_platform.dart';` to `import 'emulated_ble_platform.dart';`
- Rename `_lc` → `lcUuid`, `_char` → `bleChar`, `_deviceInfoServices` → `deviceInfoServices` (declaration + every call site in this file; there are no call sites elsewhere since they were private).

- [ ] **Step 3: Update the five test files' imports**

Replace in each file listed above:
- `import 'harness/fake_ble_platform.dart';` → `import 'package:bike_control/bluetooth/emulation/emulated_ble_platform.dart';`
- `import 'harness/fake_peripherals.dart';` → `import 'package:bike_control/bluetooth/emulation/emulated_peripherals.dart';`
- In `test/integration/harness/test_env.dart`: `import 'fake_ble_platform.dart';` → `import 'package:bike_control/bluetooth/emulation/emulated_ble_platform.dart';`
- In `test/bluetooth/front_shift_combo_test.dart`: `import '../integration/harness/fake_ble_platform.dart';` → package import as above (same for fake_peripherals).

- [ ] **Step 4: Run the affected tests**

Run: `flutter test test/integration test/bluetooth/front_shift_combo_test.dart`
Expected: all PASS (pure move; no behavior change).

- [ ] **Step 5: Run analyzer**

Run: `flutter analyze`
Expected: no new issues (in particular no unused-import or dead-code warnings in the moved files).

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "refactor(emulation): promote fake BLE harness from test/ to lib/bluetooth/emulation"
```

---

### Task 2: Real-platform factory + RoutingBlePlatform

`UniversalBle.setInstance()` replaces the platform wholesale and there is no public getter for the default, so mirror universal_ble's private `_defaultPlatform()` selection behind a conditional import, and add the routing platform that splits traffic between real and fake.

**Files:**
- Create: `lib/bluetooth/emulation/real_ble_platform.dart`, `real_ble_platform_stub.dart`, `real_ble_platform_io.dart`, `real_ble_platform_web.dart`
- Create: `lib/bluetooth/emulation/routing_ble_platform.dart`
- Test: `test/bluetooth/emulation/routing_ble_platform_test.dart`

**Interfaces:**
- Consumes: `FakeUniversalBlePlatform` (`peripherals` map, event methods) from Task 1.
- Produces: `UniversalBlePlatform createRealBlePlatform()` (top-level function, via `real_ble_platform.dart`); `class RoutingBlePlatform extends UniversalBlePlatform` with constructor `RoutingBlePlatform({required UniversalBlePlatform real, required FakeUniversalBlePlatform fake})` and public fields `real`, `fake`.

- [ ] **Step 1: Write the failing test**

Create `test/bluetooth/emulation/routing_ble_platform_test.dart`:

```dart
import 'dart:typed_data';

import 'package:bike_control/bluetooth/emulation/emulated_ble_platform.dart';
import 'package:bike_control/bluetooth/emulation/routing_ble_platform.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:universal_ble/universal_ble.dart';

class _ThrowingScanPlatform extends FakeUniversalBlePlatform {
  @override
  Future<void> startScan({ScanFilter? scanFilter, PlatformConfig? platformConfig}) async {
    throw StateError('radio off');
  }
}

void main() {
  late FakeUniversalBlePlatform real;
  late FakeUniversalBlePlatform fake;
  late RoutingBlePlatform routing;

  FakePeripheral peripheral(String id) => FakePeripheral(
        deviceId: id,
        name: 'P $id',
        services: [
          BleService('0000180f-0000-1000-8000-00805f9b34fb', const []),
        ],
      );

  setUp(() {
    real = FakeUniversalBlePlatform();
    fake = FakeUniversalBlePlatform();
    routing = RoutingBlePlatform(real: real, fake: fake);
  });

  test('dispatches per-device calls to the fake when the id is an emulated peripheral', () async {
    real.addPeripheral(peripheral('real:1'));
    fake.addPeripheral(peripheral('emulated:1'));

    await routing.connect('emulated:1');
    await routing.connect('real:1');

    expect(fake.peripherals['emulated:1']!.isConnected, isTrue);
    expect(real.peripherals['real:1']!.isConnected, isTrue);
    expect(real.peripherals.containsKey('emulated:1'), isFalse);

    expect(await routing.discoverServices('emulated:1', false), hasLength(1));
  });

  test('forwards scan results from both children through the routing instance', () async {
    final seen = <String>[];
    routing.onScanResultUpdate = (device) => seen.add(device.deviceId);

    await routing.startScan();
    real.addPeripheral(peripheral('real:1'));
    fake.addPeripheral(peripheral('emulated:1'));

    expect(seen, containsAll(['real:1', 'emulated:1']));
  });

  test('forwards connection events into the routing connectionStream', () async {
    fake.addPeripheral(peripheral('emulated:1'));
    final events = <bool>[];
    final sub = routing.connectionStream('emulated:1').listen(events.add);

    await routing.connect('emulated:1');
    await Future<void>.delayed(Duration.zero);

    expect(events, [true]);
    await sub.cancel();
  });

  test('forwards characteristic notifications to the routing onValueChange', () async {
    fake.addPeripheral(peripheral('emulated:1'));
    Uint8List? received;
    routing.onValueChange = (deviceId, characteristicId, value, timestamp) => received = value;

    fake.notify('emulated:1', '00002a00-0000-1000-8000-00805f9b34fb', const [1, 2, 3]);

    expect(received, Uint8List.fromList(const [1, 2, 3]));
  });

  test('startScan survives a dead real radio when emulated peripherals exist', () async {
    final throwing = _ThrowingScanPlatform();
    final routing2 = RoutingBlePlatform(real: throwing, fake: fake);

    fake.addPeripheral(peripheral('emulated:1'));
    await routing2.startScan(); // must not throw
  });

  test('startScan rethrows a real-radio failure when no emulated peripherals exist', () async {
    final throwing = _ThrowingScanPlatform();
    final routing2 = RoutingBlePlatform(real: throwing, fake: FakeUniversalBlePlatform());

    expect(routing2.startScan(), throwsStateError);
  });
}
```

Note: delete the stray `expect(routing2.startScan, throwsStateError, skip: ...)` line when writing the file — the two startScan cases are separate tests as shown.

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/bluetooth/emulation/routing_ble_platform_test.dart`
Expected: FAIL — `routing_ble_platform.dart` does not exist (compile error).

- [ ] **Step 3: Write the real-platform factory**

Create `lib/bluetooth/emulation/real_ble_platform.dart`:

```dart
/// Factory for the platform implementation universal_ble would have selected
/// itself. Needed because UniversalBle.setInstance() replaces the platform
/// wholesale and offers no getter for the default.
export 'real_ble_platform_stub.dart'
    if (dart.library.io) 'real_ble_platform_io.dart'
    if (dart.library.js_interop) 'real_ble_platform_web.dart';
```

Create `lib/bluetooth/emulation/real_ble_platform_stub.dart`:

```dart
import 'package:universal_ble/universal_ble.dart';

UniversalBlePlatform createRealBlePlatform() =>
    throw UnsupportedError('No BLE platform available on this target');
```

Create `lib/bluetooth/emulation/real_ble_platform_io.dart`:

```dart
import 'package:flutter/foundation.dart';
// Mirrors universal_ble's private _defaultPlatform() selection.
// ignore: implementation_imports
import 'package:universal_ble/src/universal_ble_linux/universal_ble_linux_instance_io.dart';
// ignore: implementation_imports
import 'package:universal_ble/src/universal_ble_pigeon/universal_ble_pigeon_channel.dart';
import 'package:universal_ble/universal_ble.dart';

UniversalBlePlatform createRealBlePlatform() {
  if (defaultTargetPlatform == TargetPlatform.linux) return universalBleLinuxInstance;
  return UniversalBlePigeonChannel.instance;
}
```

Create `lib/bluetooth/emulation/real_ble_platform_web.dart`:

```dart
// ignore: implementation_imports
import 'package:universal_ble/src/universal_ble_web/universal_ble_web.dart';
import 'package:universal_ble/universal_ble.dart';

UniversalBlePlatform createRealBlePlatform() => UniversalBleWeb.instance;
```

If the `universal_ble_linux_instance_io.dart` import path does not resolve (check the fork checkout under `~/.pub-cache/git/universal_ble-*/lib/src/universal_ble_linux/`), drop the Linux branch and return `UniversalBlePigeonChannel.instance` unconditionally — Linux is not a shipped BikeControl target even though a `linux/` folder exists.

- [ ] **Step 4: Write RoutingBlePlatform**

Create `lib/bluetooth/emulation/routing_ble_platform.dart`:

```dart
import 'dart:typed_data';

import 'package:universal_ble/universal_ble.dart';

import 'emulated_ble_platform.dart';

/// Splits universal_ble traffic between the real platform backend and the
/// in-memory emulation backend. Devices registered as emulated peripherals
/// route to the fake; everything else passes through untouched. Both
/// children's events are re-emitted through this instance — the one
/// Connection registers its callbacks on.
class RoutingBlePlatform extends UniversalBlePlatform {
  RoutingBlePlatform({required this.real, required this.fake}) {
    _forwardEvents(real);
    _forwardEvents(fake);
  }

  final UniversalBlePlatform real;
  final FakeUniversalBlePlatform fake;

  void _forwardEvents(UniversalBlePlatform child) {
    child.onScanResultUpdate = updateScanResult;
    child.onConnectionChange = updateConnection;
    child.onValueChange = updateCharacteristicValue;
    child.onAvailabilityChange = updateAvailability;
    child.onPairingStateChange = updatePairingState;
  }

  UniversalBlePlatform _forDevice(String deviceId) =>
      fake.peripherals.containsKey(deviceId) ? fake : real;

  @override
  Future<AvailabilityState> getBluetoothAvailabilityState() => real.getBluetoothAvailabilityState();

  @override
  Future<bool> enableBluetooth() => real.enableBluetooth();

  @override
  Future<bool> disableBluetooth() => real.disableBluetooth();

  @override
  Future<bool> hasPermissions({bool withAndroidFineLocation = false}) =>
      real.hasPermissions(withAndroidFineLocation: withAndroidFineLocation);

  @override
  Future<bool> requestPermissions({bool withAndroidFineLocation = false}) =>
      real.requestPermissions(withAndroidFineLocation: withAndroidFineLocation);

  @override
  Future<void> startScan({ScanFilter? scanFilter, PlatformConfig? platformConfig}) async {
    await fake.startScan(scanFilter: scanFilter, platformConfig: platformConfig);
    try {
      await real.startScan(scanFilter: scanFilter, platformConfig: platformConfig);
    } catch (_) {
      // A dead real radio (Bluetooth off on the dev machine) must not break
      // an emulation session; without emulated peripherals keep the error.
      if (fake.peripherals.isEmpty) rethrow;
    }
  }

  @override
  Future<void> stopScan() async {
    await fake.stopScan();
    try {
      await real.stopScan();
    } catch (_) {
      if (fake.peripherals.isEmpty) rethrow;
    }
  }

  @override
  Future<bool> isScanning() async => (await fake.isScanning()) || (await real.isScanning());

  @override
  Future<void> connect(String deviceId, {Duration? connectionTimeout, bool autoConnect = false}) =>
      _forDevice(deviceId).connect(deviceId, connectionTimeout: connectionTimeout, autoConnect: autoConnect);

  @override
  Future<void> disconnect(String deviceId) => _forDevice(deviceId).disconnect(deviceId);

  @override
  Future<List<BleService>> discoverServices(String deviceId, bool withDescriptors) =>
      _forDevice(deviceId).discoverServices(deviceId, withDescriptors);

  @override
  Future<void> setNotifiable(
    String deviceId,
    String service,
    String characteristic,
    BleInputProperty bleInputProperty,
  ) =>
      _forDevice(deviceId).setNotifiable(deviceId, service, characteristic, bleInputProperty);

  @override
  Future<Uint8List> readValue(String deviceId, String service, String characteristic, {Duration? timeout}) =>
      _forDevice(deviceId).readValue(deviceId, service, characteristic, timeout: timeout);

  @override
  Future<void> writeValue(
    String deviceId,
    String service,
    String characteristic,
    Uint8List value,
    BleOutputProperty bleOutputProperty,
  ) =>
      _forDevice(deviceId).writeValue(deviceId, service, characteristic, value, bleOutputProperty);

  @override
  Future<int> requestMtu(String deviceId, int expectedMtu) => _forDevice(deviceId).requestMtu(deviceId, expectedMtu);

  @override
  Future<int> readRssi(String deviceId) => _forDevice(deviceId).readRssi(deviceId);

  @override
  Future<void> requestConnectionPriority(String deviceId, BleConnectionPriority priority) =>
      _forDevice(deviceId).requestConnectionPriority(deviceId, priority);

  @override
  Future<bool> isPaired(String deviceId) => _forDevice(deviceId).isPaired(deviceId);

  @override
  Future<bool> pair(String deviceId) => _forDevice(deviceId).pair(deviceId);

  @override
  Future<void> unpair(String deviceId) => _forDevice(deviceId).unpair(deviceId);

  @override
  Future<BleConnectionState> getConnectionState(String deviceId) => _forDevice(deviceId).getConnectionState(deviceId);

  @override
  Future<List<BleDevice>> getSystemDevices(List<String>? withServices) => real.getSystemDevices(withServices);
}
```

- [ ] **Step 5: Run test to verify it passes**

Run: `flutter test test/bluetooth/emulation/routing_ble_platform_test.dart`
Expected: PASS (all 6 tests).

- [ ] **Step 6: Commit**

```bash
git add lib/bluetooth/emulation test/bluetooth/emulation
git commit -m "feat(emulation): RoutingBlePlatform + real-platform factory"
```

---

### Task 3: Profile model, EmulationManager, first profiles, core/main wiring

**Files:**
- Create: `lib/bluetooth/emulation/emulation_profile.dart`
- Create: `lib/bluetooth/emulation/emulation_manager.dart`
- Create: `lib/bluetooth/emulation/profiles/zwift_profiles.dart` (Click + Ride only; more in Task 7)
- Create: `lib/bluetooth/emulation/profiles/all_profiles.dart`
- Modify: `lib/bluetooth/emulation/emulated_ble_platform.dart` (add `removePeripheral`)
- Modify: `lib/utils/core.dart` (add `emulation` field near the other emulator singletons at ~line 71-79)
- Modify: `lib/main.dart` (debug install right after `WidgetsFlutterBinding.ensureInitialized()` at ~line 70)
- Test: `test/bluetooth/emulation/emulation_manager_test.dart`

**Interfaces:**
- Consumes: `FakeUniversalBlePlatform`, `FakePeripheral`, `buildZwiftClick`, `buildZwiftRide`, `autoRespondToZwiftHandshake`, `zwiftClickNotification`, `zwiftRideNotification` (Task 1); `RoutingBlePlatform`, `createRealBlePlatform()` (Task 2).
- Produces:
  - `enum EmulationCategory { controller, steering, accessory }`
  - `class EmulationProfile` with `final String name; final EmulationCategory category; final FakePeripheral Function() build; final void Function(FakeUniversalBlePlatform ble, FakePeripheral peripheral)? onRegistered; final List<EmulatedInput> Function(EmulationSession session)? inputs; final String? Function(String characteristicUuid, List<int> value)? decodeWrite;`
  - `sealed class EmulatedInput { final String label; }`, `class EmulatedButton extends EmulatedInput { final void Function() onDown; final void Function() onUp; }`, `class EmulatedAction extends EmulatedInput { final void Function() run; }`
  - `class EmulationSession` with `profile`, `peripheral`, `ble`, `ValueNotifier<List<String>> writeLog`, `late final List<EmulatedInput> inputs`, `void notify(String characteristicUuid, List<int> bytes)`, `void dropConnection()`, `void setRssi(int rssi)`
  - `class EmulationManager` with `bool get isAvailable`, `FakeUniversalBlePlatform get ble`, `void attach(FakeUniversalBlePlatform ble)`, `EmulationSession start(EmulationProfile profile)`, `bool isEmulated(String deviceId)`, `EmulationSession? sessionFor(String deviceId)`, `void stop(String deviceId)`, `@visibleForTesting void reset()`
  - `FakeUniversalBlePlatform.removePeripheral(String deviceId)`
  - `final zwiftClickProfile`, `final zwiftRideProfile` (in `zwift_profiles.dart`); `List<EmulationProfile> get allEmulationProfiles` (in `all_profiles.dart`)
  - `core.emulation` (a `late final emulation = EmulationManager();` on `Core`)

- [ ] **Step 1: Write the failing test**

Create `test/bluetooth/emulation/emulation_manager_test.dart`:

```dart
import 'dart:typed_data';

import 'package:bike_control/bluetooth/devices/zwift/constants.dart';
import 'package:bike_control/bluetooth/emulation/emulated_ble_platform.dart';
import 'package:bike_control/bluetooth/emulation/emulation_manager.dart';
import 'package:bike_control/bluetooth/emulation/emulation_profile.dart';
import 'package:bike_control/bluetooth/emulation/profiles/zwift_profiles.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:universal_ble/universal_ble.dart';

void main() {
  late FakeUniversalBlePlatform ble;
  late EmulationManager manager;

  setUp(() {
    ble = FakeUniversalBlePlatform();
    manager = EmulationManager()..attach(ble);
  });

  test('start registers the peripheral and builds the session inputs', () {
    final session = manager.start(zwiftClickProfile);

    expect(ble.peripherals.containsKey('emulated:zwift-click'), isTrue);
    expect(manager.isEmulated('emulated:zwift-click'), isTrue);
    expect(session.inputs.whereType<EmulatedButton>(), hasLength(2));
  });

  test('start is idempotent per profile', () {
    final first = manager.start(zwiftClickProfile);
    final second = manager.start(zwiftClickProfile);

    expect(identical(first, second), isTrue);
    expect(ble.peripherals, hasLength(1));
  });

  test('button input injects an encoded notification frame', () {
    final session = manager.start(zwiftClickProfile);
    Uint8List? received;
    ble.onValueChange = (deviceId, characteristicId, value, timestamp) => received = value;

    final plus = session.inputs.whereType<EmulatedButton>().first;
    plus.onDown();

    expect(received, isNotNull);
    expect(received!.first, ZwiftConstants.CLICK_NOTIFICATION_MESSAGE_TYPE);
  });

  test('app writes are decoded into the write log', () async {
    final profile = EmulationProfile(
      name: 'Sink',
      category: EmulationCategory.accessory,
      build: () => FakePeripheral(deviceId: 'emulated:sink', name: 'Sink'),
      decodeWrite: (characteristicUuid, value) => 'wrote ${value.length} bytes',
    );
    final session = manager.start(profile);

    await ble.writeValue(
      'emulated:sink',
      'service',
      'char',
      Uint8List.fromList(const [1, 2]),
      BleOutputProperty.withResponse,
    );

    expect(session.writeLog.value, ['wrote 2 bytes']);
  });

  test('stop unregisters the peripheral', () {
    manager.start(zwiftClickProfile);
    manager.stop('emulated:zwift-click');

    expect(manager.isEmulated('emulated:zwift-click'), isFalse);
    expect(ble.peripherals, isEmpty);
  });

  test('an unattached manager is inert', () {
    final detached = EmulationManager();

    expect(detached.isAvailable, isFalse);
    expect(detached.isEmulated('emulated:zwift-click'), isFalse);
    expect(() => detached.start(zwiftClickProfile), throwsStateError);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/bluetooth/emulation/emulation_manager_test.dart`
Expected: FAIL (missing files, compile error).

- [ ] **Step 3: Add removePeripheral to the fake platform**

In `lib/bluetooth/emulation/emulated_ble_platform.dart`, add below `addPeripheral`:

```dart
  /// Unregister a peripheral, dropping its connection first if needed.
  void removePeripheral(String deviceId) {
    final peripheral = peripherals.remove(deviceId);
    if (peripheral != null && peripheral.isConnected) {
      peripheral.isConnected = false;
      updateConnection(deviceId, false, 'peripheral removed');
    }
  }
```

- [ ] **Step 4: Write emulation_profile.dart**

```dart
import 'emulated_ble_platform.dart';
import 'emulation_manager.dart';

enum EmulationCategory { controller, steering, accessory }

/// One emulatable device: how to build its fake peripheral, how to script its
/// reactions, and which interactive inputs the Emulation card offers.
class EmulationProfile {
  const EmulationProfile({
    required this.name,
    required this.category,
    required this.build,
    this.onRegistered,
    this.inputs,
    this.decodeWrite,
  });

  final String name;
  final EmulationCategory category;

  /// Builds the peripheral. The deviceId must be stable and
  /// 'emulated:'-prefixed so re-adding the same profile is idempotent.
  final FakePeripheral Function() build;

  /// Scripts peripheral reactions (e.g. handshake auto-responses). Runs once
  /// when the session starts, before the write-log wrapper is installed.
  final void Function(FakeUniversalBlePlatform ble, FakePeripheral peripheral)? onRegistered;

  /// Interactive inputs for the Emulation card.
  final List<EmulatedInput> Function(EmulationSession session)? inputs;

  /// Decodes an app→device write for the write log ([characteristicUuid] is
  /// lowercase); null return = not logged.
  final String? Function(String characteristicUuid, List<int> value)? decodeWrite;
}

sealed class EmulatedInput {
  const EmulatedInput(this.label);
  final String label;
}

/// Press-and-hold button: [onDown] injects the pressed frame, [onUp] the
/// released frame — the app's real long-press/double-click timing applies.
class EmulatedButton extends EmulatedInput {
  const EmulatedButton(super.label, {required this.onDown, required this.onUp});
  final void Function() onDown;
  final void Function() onUp;
}

/// One-shot action (self-releasing protocols, calibration bursts, taps).
class EmulatedAction extends EmulatedInput {
  const EmulatedAction(super.label, {required this.run});
  final void Function() run;
}
```

- [ ] **Step 5: Write emulation_manager.dart**

```dart
import 'package:flutter/foundation.dart';
import 'package:universal_ble/universal_ble.dart';

import 'emulated_ble_platform.dart';
import 'emulation_profile.dart';

/// A live emulated device: its peripheral, profile, decoded write log and the
/// interactive inputs bound to it.
class EmulationSession {
  EmulationSession({required this.profile, required this.peripheral, required this.ble}) {
    profile.onRegistered?.call(ble, peripheral);
    final scripted = peripheral.onWrite;
    peripheral.onWrite = (service, characteristic, value) {
      scripted?.call(service, characteristic, value);
      final decoded = profile.decodeWrite?.call(characteristic.toLowerCase(), value);
      if (decoded != null) writeLog.value = [...writeLog.value, decoded];
    };
    inputs = profile.inputs?.call(this) ?? const [];
  }

  final EmulationProfile profile;
  final FakePeripheral peripheral;
  final FakeUniversalBlePlatform ble;
  final ValueNotifier<List<String>> writeLog = ValueNotifier(const []);
  late final List<EmulatedInput> inputs;

  void notify(String characteristicUuid, List<int> bytes) =>
      ble.notify(peripheral.deviceId, characteristicUuid, bytes);

  void dropConnection() => ble.dropConnection(peripheral.deviceId);

  /// Re-emits the scan result with a different RSSI (drives the signal UI).
  void setRssi(int rssi) {
    final base = peripheral.scanResult;
    ble.updateScanResult(
      BleDevice(
        deviceId: base.deviceId,
        name: peripheral.name,
        rssi: rssi,
        services: base.services,
        manufacturerDataList: base.manufacturerDataList,
      ),
    );
  }
}

/// Owns the emulated peripherals in debug builds. Never attached in release
/// builds, so it stays inert there.
class EmulationManager {
  FakeUniversalBlePlatform? _ble;
  final Map<String, EmulationSession> _sessions = {};

  bool get isAvailable => _ble != null;

  /// The fake platform the emulated peripherals live on. Only valid when
  /// [isAvailable].
  FakeUniversalBlePlatform get ble => _ble!;

  void attach(FakeUniversalBlePlatform ble) => _ble = ble;

  List<EmulationSession> get sessions => _sessions.values.toList();

  EmulationSession start(EmulationProfile profile) {
    final ble = _ble;
    if (ble == null) throw StateError('EmulationManager.attach was never called');
    final peripheral = profile.build();
    final existing = _sessions[peripheral.deviceId];
    if (existing != null) return existing;
    final session = EmulationSession(profile: profile, peripheral: peripheral, ble: ble);
    _sessions[peripheral.deviceId] = session;
    ble.addPeripheral(peripheral);
    return session;
  }

  bool isEmulated(String deviceId) => _sessions.containsKey(deviceId);

  EmulationSession? sessionFor(String deviceId) => _sessions[deviceId];

  void stop(String deviceId) {
    _sessions.remove(deviceId);
    _ble?.removePeripheral(deviceId);
  }

  /// Test hook: drop all sessions (the fake platform's own reset() clears the
  /// peripherals).
  @visibleForTesting
  void reset() => _sessions.clear();
}
```

- [ ] **Step 6: Write the first two profiles + registry**

Create `lib/bluetooth/emulation/profiles/zwift_profiles.dart`:

```dart
import 'package:bike_control/bluetooth/devices/zwift/constants.dart';
import 'package:bike_control/bluetooth/devices/zwift/zwift_ride.dart' show RideButtonMask;

import '../emulated_peripherals.dart';
import '../emulation_manager.dart';
import '../emulation_profile.dart';

void _clickFrame(EmulationSession session, {required bool plus, required bool minus}) {
  session.notify(
    ZwiftConstants.ZWIFT_ASYNC_CHARACTERISTIC_UUID,
    zwiftClickNotification(plusPressed: plus, minusPressed: minus),
  );
}

final zwiftClickProfile = EmulationProfile(
  name: 'Zwift Click',
  category: EmulationCategory.controller,
  build: () => buildZwiftClick(deviceId: 'emulated:zwift-click'),
  onRegistered: autoRespondToZwiftHandshake,
  inputs: (session) => [
    EmulatedButton(
      'Shift Up (+)',
      onDown: () => _clickFrame(session, plus: true, minus: false),
      onUp: () => _clickFrame(session, plus: false, minus: false),
    ),
    EmulatedButton(
      'Shift Down (−)',
      onDown: () => _clickFrame(session, plus: false, minus: true),
      onUp: () => _clickFrame(session, plus: false, minus: false),
    ),
  ],
);

/// Ride-protocol press/release inputs, one per app-side [RideButtonMask] bit.
/// Shared by every device speaking the Ride protobuf (Ride, Click V2 sides,
/// Play FW2).
List<EmulatedInput> rideMaskInputs(EmulationSession session, List<RideButtonMask> masks) {
  void send(List<RideButtonMask> pressed) {
    session.notify(ZwiftConstants.ZWIFT_ASYNC_CHARACTERISTIC_UUID, zwiftRideNotification(pressed: pressed));
  }

  return [
    for (final mask in masks)
      EmulatedButton(mask.name, onDown: () => send([mask]), onUp: () => send(const [])),
  ];
}

final zwiftRideProfile = EmulationProfile(
  name: 'Zwift Ride',
  category: EmulationCategory.controller,
  build: () => buildZwiftRide(deviceId: 'emulated:zwift-ride'),
  onRegistered: (ble, peripheral) =>
      autoRespondToZwiftHandshake(ble, peripheral, startResponse: ZwiftConstants.RESPONSE_START_PLAY),
  inputs: (session) => rideMaskInputs(session, RideButtonMask.values),
);
```

(The Ride handshake response mirrors `controller_button_chain_test.dart:242`, which uses `RESPONSE_START_PLAY` for the Ride and passes.)

Create `lib/bluetooth/emulation/profiles/all_profiles.dart`:

```dart
import '../emulation_profile.dart';
import 'zwift_profiles.dart';

/// Every device the debug "Emulate device" menu can add. Extended per family
/// in later tasks; keep controllers first, then steering, then accessories.
List<EmulationProfile> get allEmulationProfiles => [
      zwiftClickProfile,
      zwiftRideProfile,
    ];
```

- [ ] **Step 7: Run test to verify it passes**

Run: `flutter test test/bluetooth/emulation/emulation_manager_test.dart`
Expected: PASS (all 6 tests).

- [ ] **Step 8: Wire core and main**

In `lib/utils/core.dart`, next to the other emulator singletons (`zwiftEmulator` etc., ~line 71-79), add:

```dart
  late final emulation = EmulationManager();
```

with import `import 'package:bike_control/bluetooth/emulation/emulation_manager.dart';`.

In `lib/main.dart`, inside `runZonedGuarded`, immediately after `WidgetsFlutterBinding.ensureInitialized();` (~line 70, BEFORE the sub-window overlay dispatch), add:

```dart
      // Debug builds route BLE through the emulation-capable platform so the
      // "Emulate device" menu can add fake peripherals next to real hardware.
      // Must run before Connection.initialize() — universal_ble callbacks
      // live on the platform instance.
      if (kDebugMode) {
        final emulatedBle = FakeUniversalBlePlatform();
        UniversalBle.setInstance(RoutingBlePlatform(real: createRealBlePlatform(), fake: emulatedBle));
        core.emulation.attach(emulatedBle);
      }
```

Add imports to `lib/main.dart`:

```dart
import 'package:bike_control/bluetooth/emulation/emulated_ble_platform.dart';
import 'package:bike_control/bluetooth/emulation/real_ble_platform.dart';
import 'package:bike_control/bluetooth/emulation/routing_ble_platform.dart';
import 'package:universal_ble/universal_ble.dart';
```

(skip any already present).

- [ ] **Step 9: Analyzer + full move-affected tests**

Run: `flutter analyze`
Expected: clean.
Run: `flutter test test/bluetooth/emulation`
Expected: PASS.

- [ ] **Step 10: Commit**

```bash
git add -A
git commit -m "feat(emulation): EmulationManager, profiles model, Click/Ride profiles, debug platform install"
```

---

### Task 4: Forget hook in Connection

Forgetting an emulated device must tear down its fake peripheral and clear the scan-result dedupe cache so the same profile can be added again later (the normal `forget` path intentionally leaves `_lastScanResult` alone, which would block re-detection).

**Files:**
- Modify: `lib/bluetooth/connection.dart` (inside `disconnect(...)`, in the `if (device is BluetoothDevice)` branch, after the subscription cleanup at ~line 721-724)
- Test: `test/integration/emulation_forget_test.dart`

**Interfaces:**
- Consumes: `core.emulation.isEmulated(String)`, `core.emulation.stop(String)` (Task 3).
- Produces: behavior only (no new API).

- [ ] **Step 1: Write the failing test**

Create `test/integration/emulation_forget_test.dart`:

```dart
import 'package:bike_control/bluetooth/devices/zwift/zwift_click.dart';
import 'package:bike_control/bluetooth/emulation/profiles/zwift_profiles.dart';
import 'package:bike_control/utils/actions/base_actions.dart';
import 'package:bike_control/utils/core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'harness/test_env.dart';

Future<void> main() async {
  final env = await IntegrationEnv.setUp();

  core.connection.initialize();

  setUp(() async {
    await env.resetState();
    core.actionHandler = StubActions();
    core.emulation.reset();
    core.emulation.attach(env.ble);
  });

  tearDown(() async {
    await env.resetConnection();
  });

  Future<ZwiftClick> connect() async {
    core.emulation.start(zwiftClickProfile);
    await core.connection.performScanning();
    await IntegrationEnv.waitFor(
      () => core.connection.devices.whereType<ZwiftClick>().isNotEmpty,
      description: 'emulated Zwift Click in device list',
    );
    return core.connection.devices.whereType<ZwiftClick>().first;
  }

  test('forgetting an emulated device unregisters its peripheral', () async {
    final device = await connect();

    await core.connection.disconnect(device, forget: true, persistForget: false);

    expect(core.emulation.isEmulated('emulated:zwift-click'), isFalse);
    expect(env.ble.peripherals, isEmpty);
    expect(core.connection.devices, isEmpty);
  });

  test('the same profile can be re-added after forgetting (scan cache cleared)', () async {
    final device = await connect();
    await core.connection.disconnect(device, forget: true, persistForget: false);

    final again = await connect();

    expect(again.isConnected, isTrue);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/integration/emulation_forget_test.dart`
Expected: first test FAILS on `expect(env.ble.peripherals, isEmpty)` (peripheral still registered); second test FAILS on the waitFor timeout (device never re-detected because `_lastScanResult` still holds the id).

- [ ] **Step 3: Add the hook**

In `lib/bluetooth/connection.dart`, `disconnect(...)`: locate the subscription cleanup inside the `if (device is BluetoothDevice)` branch:

```dart
    _streamSubscriptions[device]?.cancel();
    _streamSubscriptions.remove(device);
    _connectionSubscriptions[device]?.cancel();
    _connectionSubscriptions.remove(device);
```

Immediately after it, add:

```dart
    // Forgetting an emulated device tears down its fake peripheral and clears
    // the scan-result dedupe cache so the same profile can be re-added later.
    if (forget && core.emulation.isEmulated(device.device.deviceId)) {
      core.emulation.stop(device.device.deviceId);
      _lastScanResult.removeWhere((d) => d.deviceId == device.device.deviceId);
    }
```

(`core` is already imported in connection.dart.)

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/integration/emulation_forget_test.dart`
Expected: PASS (both tests).

- [ ] **Step 5: Regression-run the other integration tests**

Run: `flutter test test/integration`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/bluetooth/connection.dart test/integration/emulation_forget_test.dart
git commit -m "feat(emulation): unregister emulated peripheral on forget"
```

---

### Task 5: "Emulate device" debug menu

Replace the hard-coded debug "Continue" menu item with a submenu listing every emulation profile. Declarative debug-only UI — verified by analyzer + a manual smoke check; the behavior underneath (manager/scanning) is already unit- and integration-tested.

**Files:**
- Modify: `lib/widgets/menu.dart` (the "Continue" `MenuButton` at lines 186-222)

**Interfaces:**
- Consumes: `allEmulationProfiles` (Task 3), `core.emulation.start(profile)`, `core.connection.performScanning()`.
- Produces: none (UI only).

- [ ] **Step 1: Replace the Continue button**

In `lib/widgets/menu.dart`, inside the first `if (kDebugMode) ...[` block, delete the entire "Continue" `MenuButton` (the one whose child is `Text(context.i18n.continueAction)`, including the commented-out overlay experiment inside its `onPressed`, lines ~187-222) and replace it with:

```dart
              MenuButton(
                child: const Text('Emulate device'),
                subMenu: [
                  for (final profile in allEmulationProfiles)
                    MenuButton(
                      child: Text(profile.name),
                      onPressed: (c) {
                        core.emulation.start(profile);
                        unawaited(core.connection.performScanning());
                      },
                    ),
                ],
              ),
```

Add imports to `menu.dart`:

```dart
import 'dart:async';

import 'package:bike_control/bluetooth/emulation/profiles/all_profiles.dart';
```

Remove imports that the deletion orphaned (likely `zwift_clickv2.dart` and any now-unused ones — let the analyzer decide in Step 2).

- [ ] **Step 2: Analyzer**

Run: `flutter analyze`
Expected: clean (no unused imports, no missing identifiers).

- [ ] **Step 3: Manual smoke check**

Run the app in debug on the desktop (`flutter run -d macos`), open the ⋮ menu → "Emulate device" → pick "Zwift Click". Expected: a "Zwift Click" device appears in the controllers list and connects (green status), with battery 88% and FW 1.1.0 from the fake device-info service.

- [ ] **Step 4: Commit**

```bash
git add lib/widgets/menu.dart
git commit -m "feat(emulation): replace debug Continue button with Emulate device menu"
```

---

### Task 6: Emulation card on ControllerSettingsPage

An "Emulation" section on the per-device settings page, rendered only for emulated devices: press-and-hold buttons / one-shot actions from the session's inputs, the decoded write log, and connection controls.

**Files:**
- Create: `lib/widgets/emulation_card.dart`
- Modify: `lib/pages/controller_settings.dart` (insert between the Preferences block ending ~line 97 and `_buildActions` at ~line 100)
- Test: `test/widgets/emulation_card_test.dart`

**Interfaces:**
- Consumes: `EmulationSession` (`inputs`, `writeLog`, `dropConnection()`, `setRssi(int)`), `EmulatedButton`/`EmulatedAction` (Task 3).
- Produces: `class EmulationCard extends StatelessWidget { const EmulationCard({super.key, required this.session}); final EmulationSession session; }`

- [ ] **Step 1: Write the failing test**

Create `test/widgets/emulation_card_test.dart`:

```dart
import 'dart:typed_data';

import 'package:bike_control/bluetooth/devices/zwift/constants.dart';
import 'package:bike_control/bluetooth/emulation/emulated_ble_platform.dart';
import 'package:bike_control/bluetooth/emulation/emulation_manager.dart';
import 'package:bike_control/bluetooth/emulation/emulation_profile.dart';
import 'package:bike_control/bluetooth/emulation/profiles/zwift_profiles.dart';
import 'package:bike_control/gen/l10n.dart';
import 'package:bike_control/widgets/emulation_card.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:universal_ble/universal_ble.dart';

Future<void> main() async {
  await AppLocalizations.load(const Locale('en'));

  late FakeUniversalBlePlatform ble;
  late EmulationManager manager;

  setUp(() {
    ble = FakeUniversalBlePlatform();
    manager = EmulationManager()..attach(ble);
  });

  Future<void> pumpCard(WidgetTester tester, EmulationSession session) async {
    await tester.pumpWidget(
      ShadcnApp(
        localizationsDelegates: const [AppLocalizations.delegate],
        supportedLocales: const [Locale('en')],
        home: Scaffold(child: SingleChildScrollView(child: EmulationCard(session: session))),
      ),
    );
    await tester.pump();
  }

  testWidgets('renders one control per input plus the connection controls', (tester) async {
    final session = manager.start(zwiftClickProfile);
    await pumpCard(tester, session);

    expect(find.text('Shift Up (+)'), findsOneWidget);
    expect(find.text('Shift Down (−)'), findsOneWidget);
    expect(find.text('Drop connection'), findsOneWidget);
    expect(find.text('Weak signal'), findsOneWidget);
    expect(find.text('Strong signal'), findsOneWidget);
  });

  testWidgets('press and release inject pressed and released frames', (tester) async {
    final session = manager.start(zwiftClickProfile);
    final frames = <Uint8List>[];
    ble.onValueChange = (deviceId, characteristicId, value, timestamp) => frames.add(value);
    await pumpCard(tester, session);

    final gesture = await tester.startGesture(tester.getCenter(find.text('Shift Up (+)')));
    await tester.pump(const Duration(milliseconds: 50));
    await gesture.up();
    await tester.pump();

    expect(frames, hasLength(2));
    expect(frames.first.first, ZwiftConstants.CLICK_NOTIFICATION_MESSAGE_TYPE);
    expect(frames.last.first, ZwiftConstants.CLICK_NOTIFICATION_MESSAGE_TYPE);
  });

  testWidgets('write log renders decoded writes', (tester) async {
    final profile = EmulationProfile(
      name: 'Sink',
      category: EmulationCategory.accessory,
      build: () => FakePeripheral(deviceId: 'emulated:sink', name: 'Sink'),
      decodeWrite: (characteristicUuid, value) => 'Set incline 6.0%',
    );
    final session = manager.start(profile);
    await pumpCard(tester, session);

    await ble.writeValue(
      'emulated:sink',
      'service',
      'char',
      Uint8List.fromList(const [0x0a, 0x3c, 0x00]),
      BleOutputProperty.withResponse,
    );
    await tester.pump();

    expect(find.text('Set incline 6.0%'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/widgets/emulation_card_test.dart`
Expected: FAIL — `emulation_card.dart` does not exist.

- [ ] **Step 3: Write the widget**

Create `lib/widgets/emulation_card.dart`:

```dart
import 'package:bike_control/bluetooth/emulation/emulation_manager.dart';
import 'package:bike_control/bluetooth/emulation/emulation_profile.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

/// Debug-only interactive controls for an emulated device: inject protocol
/// frames per input, review decoded app→device writes, and exercise the
/// connection UX (drop / signal strength).
class EmulationCard extends StatelessWidget {
  const EmulationCard({super.key, required this.session});

  final EmulationSession session;

  @override
  Widget build(BuildContext context) {
    return Card(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 12,
        children: [
          if (session.inputs.isNotEmpty)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [for (final input in session.inputs) _buildInput(input)],
            ),
          ValueListenableBuilder<List<String>>(
            valueListenable: session.writeLog,
            builder: (context, log, _) {
              if (log.isEmpty) return const SizedBox.shrink();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 4,
                children: [
                  const Text('WRITES FROM APP').xSmall.bold.muted,
                  for (final line in log.reversed.take(8)) Text(line).xSmall.muted,
                ],
              );
            },
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlineButton(
                size: ButtonSize.small,
                onPressed: session.dropConnection,
                child: const Text('Drop connection'),
              ),
              OutlineButton(
                size: ButtonSize.small,
                onPressed: () => session.setRssi(-85),
                child: const Text('Weak signal'),
              ),
              OutlineButton(
                size: ButtonSize.small,
                onPressed: () => session.setRssi(-50),
                child: const Text('Strong signal'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInput(EmulatedInput input) {
    return switch (input) {
      EmulatedButton button => Button(
          style: ButtonStyle.outline(),
          onPressed: () {},
          onTapDown: (_) => button.onDown(),
          onTapUp: (_) => button.onUp(),
          child: Text(button.label),
        ),
      EmulatedAction action => Button(
          style: ButtonStyle.outline(),
          onPressed: action.run,
          child: Text(action.label),
        ),
    };
  }
}
```

Note: shadcn's `Button` supports `onTapDown`/`onTapUp` — the same pattern `ButtonSimulator._buildButton` uses (`lib/pages/button_simulator.dart:570-579`). If `onTapUp` doesn't fire on gesture cancel, that's acceptable for a debug tool.

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/widgets/emulation_card_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 5: Wire into ControllerSettingsPage**

In `lib/pages/controller_settings.dart`, in `build`'s main `Column`, after the Preferences conditional block (`if (device.buildPreferences(context) != null) ...[ ... ]`, ends ~line 97) and before `_buildActions(device, keymap)` (~line 100), insert:

```dart
            if (kDebugMode && device is BluetoothDevice && core.emulation.isAvailable) ...[
              if (core.emulation.sessionFor((device as BluetoothDevice).device.deviceId) case final session?) ...[
                _buildSectionHeader('Emulation'),
                const Gap(16),
                EmulationCard(session: session),
                const Gap(24),
              ],
            ],
```

Match the local naming in the method: `build` assigns `final device = widget.device;` — if `device` is already promoted/typed differently, adapt the cast accordingly (`widget.device is BluetoothDevice`, then `(widget.device as BluetoothDevice).device.deviceId`). Use the existing `_buildSectionHeader` helper; if its signature requires more arguments (see its uses at ~lines 83-95), pass the section title only, mirroring the Preferences call.

Add imports:

```dart
import 'package:bike_control/bluetooth/devices/bluetooth_device.dart';
import 'package:bike_control/bluetooth/emulation/emulation_manager.dart';
import 'package:bike_control/widgets/emulation_card.dart';
import 'package:flutter/foundation.dart';
```

(skip any already present; `kDebugMode` may come via shadcn_flutter's re-export of foundation — analyzer will tell.)

- [ ] **Step 6: Analyzer + tests**

Run: `flutter analyze`
Expected: clean.
Run: `flutter test test/widgets/emulation_card_test.dart test/pages`
Expected: PASS.

- [ ] **Step 7: Manual smoke check**

`flutter run -d macos` → menu → Emulate device → Zwift Click → tap the device card → ControllerSettingsPage shows an "Emulation" section; press-and-hold "Shift Up (+)" fires the mapped action (visible in the activity log on the overview); "Drop connection" grays the device out and it auto-reconnects via the scan.

- [ ] **Step 8: Commit**

```bash
git add lib/widgets/emulation_card.dart lib/pages/controller_settings.dart test/widgets/emulation_card_test.dart
git commit -m "feat(emulation): Emulation card on controller settings page"
```

---

### Task 7: Remaining Zwift profiles (Play L/R, Play FW2, Click V2 L/R)

All share the Zwift custom-service GATT. Play speaks the `PlayKeyPadStatus` protobuf; FW2 and Click V2 speak the Ride protobuf (app-side `RideButtonMask`). Click V2 sides additionally expose the two ClickLogic unlock characteristics (writes accepted, never answered — buttons decode regardless because `CONTROLLER_NOTIFICATION` frames are processed independently of the pairing exchange).

**Files:**
- Modify: `lib/bluetooth/emulation/profiles/zwift_profiles.dart`
- Modify: `lib/bluetooth/emulation/profiles/all_profiles.dart`
- Test: `test/integration/emulation_zwift_profiles_test.dart`

**Interfaces:**
- Consumes: `rideMaskInputs(...)` (Task 3), `lcUuid`/`bleChar`/`deviceInfoServices` (Task 1), `EmulationSession.notify`.
- Produces: `FakePeripheral buildZwiftController({required String deviceId, required String name, required int manufacturerType, List<String> extraCharacteristicUuids = const []})`; `List<int> zwiftPlayNotification({required bool rightPad, bool primary, bool secondary, bool tertiary, bool quaternary, bool shoulder, bool onOff, int analogLR})`; profiles `zwiftPlayLeftProfile`, `zwiftPlayRightProfile`, `zwiftPlayFw2Profile`, `zwiftClickV2LeftProfile`, `zwiftClickV2RightProfile`.

- [ ] **Step 1: Write the failing test**

Create `test/integration/emulation_zwift_profiles_test.dart`:

```dart
import 'package:bike_control/bluetooth/devices/bluetooth_device.dart';
import 'package:bike_control/bluetooth/devices/zwift/zwift_clickv2_left_side.dart';
import 'package:bike_control/bluetooth/devices/zwift/zwift_clickv2_right_side.dart';
import 'package:bike_control/bluetooth/devices/zwift/zwift_play.dart';
import 'package:bike_control/bluetooth/devices/zwift/zwift_play_fw2.dart';
import 'package:bike_control/bluetooth/emulation/emulation_profile.dart';
import 'package:bike_control/bluetooth/emulation/profiles/zwift_profiles.dart';
import 'package:bike_control/utils/actions/base_actions.dart';
import 'package:bike_control/utils/core.dart';
import 'package:bike_control/utils/keymap/apps/zwift.dart';
import 'package:bike_control/utils/keymap/buttons.dart';
import 'package:flutter_test/flutter_test.dart';

import 'harness/test_env.dart';

Future<void> main() async {
  final env = await IntegrationEnv.setUp();
  late StubActions stubActions;

  core.connection.initialize();

  setUp(() async {
    await env.resetState();
    stubActions = StubActions();
    stubActions.supportedApp = Zwift();
    core.actionHandler = stubActions;
    core.emulation.reset();
    core.emulation.attach(env.ble);
  });

  tearDown(() async {
    await env.resetConnection();
  });

  /// Starts [profile], waits for detection as [T] and for the handshake write.
  Future<EmulatedButton> connectAndFirstButton<T extends BluetoothDevice>(
    EmulationProfile profile,
    String deviceId, {
    String? buttonLabel,
  }) async {
    final session = core.emulation.start(profile);
    await core.connection.performScanning();
    await IntegrationEnv.waitFor(
      () => core.connection.devices.whereType<T>().isNotEmpty,
      description: '$T in device list',
    );
    await IntegrationEnv.waitFor(
      () => session.peripheral.writes.isNotEmpty,
      description: '$T handshake write',
    );
    final buttons = session.inputs.whereType<EmulatedButton>();
    return buttonLabel == null ? buttons.first : buttons.firstWhere((b) => b.label == buttonLabel);
  }

  Future<void> pressAndAssert(EmulatedButton button, ControllerButton expected) async {
    button.onDown();
    button.onUp();
    await IntegrationEnv.waitFor(() => stubActions.performedActions.isNotEmpty, description: 'performed action');
    expect(stubActions.performedActions.map((a) => a.button), contains(expected));
  }

  test('Zwift Play left: Nav Up press performs navigationUp', () async {
    final button = await connectAndFirstButton<ZwiftPlay>(
      zwiftPlayLeftProfile,
      'emulated:zwift-play-left',
      buttonLabel: 'Nav Up',
    );
    await pressAndAssert(button, ZwiftButtons.navigationUp);
  });

  test('Zwift Play right: Y press performs y', () async {
    final button = await connectAndFirstButton<ZwiftPlay>(
      zwiftPlayRightProfile,
      'emulated:zwift-play-right',
      buttonLabel: 'Y',
    );
    await pressAndAssert(button, ZwiftButtons.y);
  });

  test('Zwift Play FW2: SHFT_UP_R press performs shiftUpRight', () async {
    final button = await connectAndFirstButton<ZwiftPlayFw2>(
      zwiftPlayFw2Profile,
      'emulated:zwift-play-fw2',
      buttonLabel: 'SHFT_UP_R_BTN',
    );
    await pressAndAssert(button, ZwiftButtons.shiftUpRight);
  });

  test('Zwift Click V2 left side: UP press performs navigationUp', () async {
    final button = await connectAndFirstButton<ZwiftClickV2LeftSide>(
      zwiftClickV2LeftProfile,
      'emulated:zwift-clickv2-left',
      buttonLabel: 'UP_BTN',
    );
    await pressAndAssert(button, ZwiftButtons.navigationUp);
  });

  test('Zwift Click V2 right side: A press performs a', () async {
    final button = await connectAndFirstButton<ZwiftClickV2RightSide>(
      zwiftClickV2RightProfile,
      'emulated:zwift-clickv2-right',
      buttonLabel: 'A_BTN',
    );
    await pressAndAssert(button, ZwiftButtons.a);
  });
}
```

Button-label caveat: `rideMaskInputs` labels buttons by the app-side enum name (`UP_BTN`, `SHFT_UP_R_BTN`, `A_BTN` — see `RideButtonMask` in `lib/bluetooth/devices/zwift/zwift_ride.dart:264-288`); confirm exact enum-value names when writing the test. The expected `ZwiftButtons.*` mapping is in `zwift_ride.dart:188-204`.

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/integration/emulation_zwift_profiles_test.dart`
Expected: FAIL — the five profiles don't exist (compile error).

- [ ] **Step 3: Implement builders, encoder, profiles**

Append to `lib/bluetooth/emulation/profiles/zwift_profiles.dart` (extend the existing imports with `dart:typed_data`, `package:prop/prop.dart` — remember `hide RideButtonMask` — and `package:universal_ble/universal_ble.dart`):

```dart
/// Generic Zwift-controller peripheral: custom service with async / syncTx /
/// syncRx, plus optional extra writable characteristics (Click V2 unlock).
FakePeripheral buildZwiftController({
  required String deviceId,
  required String name,
  required int manufacturerType,
  List<String> extraCharacteristicUuids = const [],
}) {
  final peripheral = FakePeripheral(
    deviceId: deviceId,
    name: name,
    advertisedServices: [lcUuid(ZwiftConstants.ZWIFT_CUSTOM_SERVICE_UUID)],
    manufacturerData: ManufacturerData(
      ZwiftConstants.ZWIFT_MANUFACTURER_ID,
      Uint8List.fromList([manufacturerType]),
    ),
  );
  peripheral.services.addAll([
    BleService(lcUuid(ZwiftConstants.ZWIFT_CUSTOM_SERVICE_UUID), [
      bleChar(ZwiftConstants.ZWIFT_ASYNC_CHARACTERISTIC_UUID, [CharacteristicProperty.notify]),
      bleChar(ZwiftConstants.ZWIFT_SYNC_TX_CHARACTERISTIC_UUID, [CharacteristicProperty.indicate]),
      bleChar(ZwiftConstants.ZWIFT_SYNC_RX_CHARACTERISTIC_UUID, [
        CharacteristicProperty.write,
        CharacteristicProperty.writeWithoutResponse,
      ]),
      for (final uuid in extraCharacteristicUuids)
        bleChar(uuid, [CharacteristicProperty.write, CharacteristicProperty.writeWithoutResponse]),
    ]),
    ...deviceInfoServices(peripheral, firmware: '1.3.0'),
  ]);
  return peripheral;
}

/// Encodes a Zwift Play keypad notification. ON (= pressed) is the protobuf
/// default, so every field is set explicitly — the all-OFF frame is the
/// release frame. [analogLR] of ±100 emulates a full paddle deflection.
List<int> zwiftPlayNotification({
  required bool rightPad,
  bool primary = false, // Y (right pad) / nav up (left pad)
  bool secondary = false, // Z / nav left
  bool tertiary = false, // A / nav right
  bool quaternary = false, // B / nav down
  bool shoulder = false, // side button
  bool onOff = false,
  int analogLR = 0,
}) {
  PlayButtonStatus s(bool pressed) => pressed ? PlayButtonStatus.ON : PlayButtonStatus.OFF;
  final status = PlayKeyPadStatus(
    rightPad: s(rightPad),
    buttonYUp: s(primary),
    buttonZLeft: s(secondary),
    buttonARight: s(tertiary),
    buttonBDown: s(quaternary),
    buttonShift: s(shoulder),
    buttonOn: s(onOff),
    analogLR: analogLR,
    analogUD: 0,
  );
  return [ZwiftConstants.PLAY_NOTIFICATION_MESSAGE_TYPE, ...status.writeToBuffer()];
}

EmulationProfile _zwiftPlayProfile({required bool right}) {
  final side = right ? 'right' : 'left';
  return EmulationProfile(
    name: 'Zwift Play ($side)',
    category: EmulationCategory.controller,
    build: () => buildZwiftController(
      deviceId: 'emulated:zwift-play-$side',
      name: 'Zwift Play',
      manufacturerType: right ? ZwiftConstants.RC1_RIGHT_SIDE : ZwiftConstants.RC1_LEFT_SIDE,
    ),
    onRegistered: (ble, peripheral) =>
        autoRespondToZwiftHandshake(ble, peripheral, startResponse: ZwiftConstants.RESPONSE_START_PLAY),
    inputs: (session) {
      void send({
        bool primary = false,
        bool secondary = false,
        bool tertiary = false,
        bool quaternary = false,
        bool shoulder = false,
        bool onOff = false,
        int analogLR = 0,
      }) {
        session.notify(
          ZwiftConstants.ZWIFT_ASYNC_CHARACTERISTIC_UUID,
          zwiftPlayNotification(
            rightPad: right,
            primary: primary,
            secondary: secondary,
            tertiary: tertiary,
            quaternary: quaternary,
            shoulder: shoulder,
            onOff: onOff,
            analogLR: analogLR,
          ),
        );
      }

      EmulatedButton button(String label, void Function() down) =>
          EmulatedButton(label, onDown: down, onUp: () => send());

      return [
        button(right ? 'Y' : 'Nav Up', () => send(primary: true)),
        button(right ? 'Z' : 'Nav Left', () => send(secondary: true)),
        button(right ? 'A' : 'Nav Right', () => send(tertiary: true)),
        button(right ? 'B' : 'Nav Down', () => send(quaternary: true)),
        button('Side button', () => send(shoulder: true)),
        button('On/Off', () => send(onOff: true)),
        button('Paddle', () => send(analogLR: right ? 100 : -100)),
      ];
    },
  );
}

final zwiftPlayLeftProfile = _zwiftPlayProfile(right: false);
final zwiftPlayRightProfile = _zwiftPlayProfile(right: true);

final zwiftPlayFw2Profile = EmulationProfile(
  name: 'Zwift Play (FW2)',
  category: EmulationCategory.controller,
  build: () => buildZwiftController(
    deviceId: 'emulated:zwift-play-fw2',
    name: 'Zwift Play',
    manufacturerType: ZwiftConstants.RC1_FW2,
  ),
  onRegistered: autoRespondToZwiftHandshake,
  inputs: (session) => rideMaskInputs(session, RideButtonMask.values),
);

const _clickV2UnlockCharacteristics = [
  '00000100-19ca-4651-86e5-fa29dcdd09d1',
  '00000101-19ca-4651-86e5-fa29dcdd09d1',
];

final zwiftClickV2LeftProfile = EmulationProfile(
  name: 'Zwift Click V2 (left)',
  category: EmulationCategory.controller,
  build: () => buildZwiftController(
    deviceId: 'emulated:zwift-clickv2-left',
    name: 'Zwift Click',
    manufacturerType: ZwiftConstants.CLICK_V2_LEFT_SIDE,
    extraCharacteristicUuids: _clickV2UnlockCharacteristics,
  ),
  onRegistered: (ble, peripheral) =>
      autoRespondToZwiftHandshake(ble, peripheral, startResponse: ZwiftConstants.RESPONSE_START_CLICK_V2),
  inputs: (session) => rideMaskInputs(session, [
    RideButtonMask.UP_BTN,
    RideButtonMask.DOWN_BTN,
    RideButtonMask.LEFT_BTN,
    RideButtonMask.RIGHT_BTN,
    RideButtonMask.SHFT_UP_L_BTN,
  ]),
);

final zwiftClickV2RightProfile = EmulationProfile(
  name: 'Zwift Click V2 (right)',
  category: EmulationCategory.controller,
  build: () => buildZwiftController(
    deviceId: 'emulated:zwift-clickv2-right',
    name: 'Zwift Click',
    manufacturerType: ZwiftConstants.CLICK_V2_RIGHT_SIDE,
    extraCharacteristicUuids: _clickV2UnlockCharacteristics,
  ),
  onRegistered: (ble, peripheral) =>
      autoRespondToZwiftHandshake(ble, peripheral, startResponse: ZwiftConstants.RESPONSE_START_CLICK_V2),
  inputs: (session) => rideMaskInputs(session, [
    RideButtonMask.A_BTN,
    RideButtonMask.B_BTN,
    RideButtonMask.Y_BTN,
    RideButtonMask.Z_BTN,
    RideButtonMask.SHFT_UP_R_BTN,
  ]),
);
```

Exact `RideButtonMask` value names: check `lib/bluetooth/devices/zwift/zwift_ride.dart:264-288` and use them verbatim (the table there defines `LEFT_BTN, UP_BTN, RIGHT_BTN, DOWN_BTN, A_BTN, B_BTN, Y_BTN, Z_BTN, SHFT_UP_L_BTN?, ...` — adjust the `_BTN` suffixes to the real declarations).

Update `all_profiles.dart`:

```dart
List<EmulationProfile> get allEmulationProfiles => [
      zwiftClickProfile,
      zwiftClickV2LeftProfile,
      zwiftClickV2RightProfile,
      zwiftPlayLeftProfile,
      zwiftPlayRightProfile,
      zwiftPlayFw2Profile,
      zwiftRideProfile,
    ];
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/integration/emulation_zwift_profiles_test.dart`
Expected: PASS (5 tests). Known risk: the Click V2 side classes run `ClickLogic` (pairing GET + possible periodic reset). If a side test hangs on detection or the button never fires, check whether `core.settings.getUnlockWithZwift()` defaults matter and whether `ClickLogic.processData` swallows the frame; as a fallback assert a `ButtonNotification` on `core.connection.actionStream` instead of `performedActions`, and document the deviation in the test comment.

- [ ] **Step 5: Commit**

```bash
git add lib/bluetooth/emulation/profiles test/integration/emulation_zwift_profiles_test.dart
git commit -m "feat(emulation): Zwift Play, Play FW2 and Click V2 profiles"
```

---

### Task 8: Elite profiles (Sterzo, Square, Rizer)

Sterzo/Rizer steer via float32-LE angle notifications after a 10-sample zero calibration; Sterzo needs its challenge handshake scripted. Square sends 12-byte frames with a 4-byte button code. Rizer is steering + an incline write sink.

**Files:**
- Create: `lib/bluetooth/emulation/profiles/elite_profiles.dart`
- Modify: `lib/bluetooth/emulation/profiles/all_profiles.dart`
- Test: `test/integration/emulation_elite_profiles_test.dart`

**Interfaces:**
- Consumes: harness helpers (Task 1), `EmulationSession` (Task 3).
- Produces: `List<int> steeringAngleBytes(double degrees)`; `List<EmulatedInput> steeringInputs(EmulationSession session, String measurementCharacteristicUuid)`; profiles `eliteSterzoProfile`, `eliteSquareProfile`, `eliteRizerProfile`.

- [ ] **Step 1: Write the failing test**

Create `test/integration/emulation_elite_profiles_test.dart`:

```dart
import 'package:bike_control/bluetooth/devices/elite/elite_rizer.dart';
import 'package:bike_control/bluetooth/devices/elite/elite_square.dart';
import 'package:bike_control/bluetooth/devices/elite/elite_sterzo.dart';
import 'package:bike_control/bluetooth/emulation/emulation_profile.dart';
import 'package:bike_control/bluetooth/emulation/profiles/elite_profiles.dart';
import 'package:bike_control/utils/actions/base_actions.dart';
import 'package:bike_control/utils/core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'harness/test_env.dart';

Future<void> main() async {
  final env = await IntegrationEnv.setUp();
  late StubActions stubActions;

  core.connection.initialize();

  setUp(() async {
    await env.resetState();
    stubActions = StubActions();
    core.actionHandler = stubActions;
    core.emulation.reset();
    core.emulation.attach(env.ble);
  });

  tearDown(() async {
    await env.resetConnection();
  });

  test('Sterzo: challenge handshake completes and steering right fires rightSteer', () async {
    final session = core.emulation.start(eliteSterzoProfile);
    await core.connection.performScanning();
    await IntegrationEnv.waitFor(
      () => core.connection.devices.whereType<EliteSterzo>().isNotEmpty,
      description: 'Sterzo detected',
    );
    // The app requests the challenge with [0x03, 0x10] during handleServices.
    await IntegrationEnv.waitFor(
      () => session.peripheral.writes.any((w) => w.value.length >= 2 && w.value[0] == 0x03 && w.value[1] == 0x10),
      description: 'challenge request write',
    );
    // Challenge answer [0x03, 0x11, ...] follows (code table fetch falls back
    // to [0x96, 0x96] because HTTP is blocked in tests).
    await IntegrationEnv.waitFor(
      () => session.peripheral.writes.any((w) => w.value.length >= 2 && w.value[0] == 0x03 && w.value[1] == 0x11),
      timeout: const Duration(seconds: 5),
      description: 'challenge response write',
    );

    session.inputs.whereType<EmulatedAction>().firstWhere((a) => a.label.startsWith('Calibrate')).run();
    session.inputs.whereType<EmulatedAction>().firstWhere((a) => a.label.startsWith('Steer right')).run();

    await IntegrationEnv.waitFor(
      () => stubActions.performedActions.any((a) => a.button == SterzoButtons.rightSteer),
      timeout: const Duration(seconds: 3),
      description: 'rightSteer performed',
    );
  });

  test('Square: A button press performs EliteSquareButtons.a', () async {
    final session = core.emulation.start(eliteSquareProfile);
    await core.connection.performScanning();
    await IntegrationEnv.waitFor(
      () => core.connection.devices.whereType<EliteSquare>().isNotEmpty,
      description: 'Square detected',
    );

    final a = session.inputs.whereType<EmulatedButton>().firstWhere((b) => b.label == 'A');
    a.onDown();
    a.onUp();

    await IntegrationEnv.waitFor(() => stubActions.performedActions.isNotEmpty, description: 'square action');
    expect(stubActions.performedActions.map((x) => x.button), contains(EliteSquareButtons.a));
  });

  test('Rizer: steering fires rightSteer and incline writes are logged', () async {
    final session = core.emulation.start(eliteRizerProfile);
    await core.connection.performScanning();
    await IntegrationEnv.waitFor(
      () => core.connection.devices.whereType<EliteRizer>().isNotEmpty,
      description: 'Rizer detected',
    );
    final device = core.connection.devices.whereType<EliteRizer>().first;

    session.inputs.whereType<EmulatedAction>().firstWhere((a) => a.label.startsWith('Calibrate')).run();
    session.inputs.whereType<EmulatedAction>().firstWhere((a) => a.label.startsWith('Steer right')).run();
    await IntegrationEnv.waitFor(
      () => stubActions.performedActions.any((a) => a.button == RizerButtons.rightSteer),
      timeout: const Duration(seconds: 3),
      description: 'rizer rightSteer performed',
    );

    await device.writeInclineRaw(600); // +6.00% → tenths 60 → [0x0a, 0x3c, 0x00]
    await IntegrationEnv.waitFor(
      () => session.peripheral.writes.any(
        (w) => w.value.length == 3 && w.value[0] == 0x0a && w.value[1] == 0x3c && w.value[2] == 0x00,
      ),
      description: 'incline write',
    );
    expect(session.writeLog.value, contains('Set incline 6.0%'));
  });
}
```

Button-constant names (`SterzoButtons.rightSteer`, `EliteSquareButtons.a`, `RizerButtons.rightSteer`) are declared in the respective device files (`elite_sterzo.dart:388-402`, `elite_square.dart:108-155`, `elite_rizer.dart:35-39`) — verify exact identifiers when writing. `writeInclineRaw`'s exact signature is at `elite_rizer.dart:146-163`; adjust the `await` if it returns void.

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/integration/emulation_elite_profiles_test.dart`
Expected: FAIL — `elite_profiles.dart` does not exist.

- [ ] **Step 3: Implement**

Create `lib/bluetooth/emulation/profiles/elite_profiles.dart`:

```dart
import 'dart:typed_data';

import 'package:universal_ble/universal_ble.dart';

import '../emulated_ble_platform.dart';
import '../emulated_peripherals.dart';
import '../emulation_manager.dart';
import '../emulation_profile.dart';

/// All three Elite devices share the same base service UUID.
const _eliteServiceUuid = '347b0001-7635-408b-8918-8ff3949ce592';

// Sterzo (also the Rizer steering characteristic).
const _steeringMeasurementUuid = '347b0030-7635-408b-8918-8ff3949ce592';
const _sterzoControlUuid = '347b0031-7635-408b-8918-8ff3949ce592';
const _sterzoChallengeUuid = '347b0032-7635-408b-8918-8ff3949ce592';

// Square.
const _squareCharacteristicUuid = '347b0043-7635-408b-8918-8ff3949ce592';

// Rizer.
const _rizerWriteUuid = '347b0020-7635-408b-8918-8ff3949ce592';
const _rizerStatusUuid = '347b0021-7635-408b-8918-8ff3949ce592';
const _rizerInclineUuid = '347b0022-7635-408b-8918-8ff3949ce592';

/// Steering angle as the devices send it: float32 little-endian degrees.
List<int> steeringAngleBytes(double degrees) {
  final data = ByteData(4)..setFloat32(0, degrees, Endian.little);
  return data.buffer.asUint8List().toList();
}

/// Shared steering controls. The app averages the first 10 samples into a
/// zero offset, so Calibrate must run once before the steer actions.
List<EmulatedInput> steeringInputs(EmulationSession session, String measurementCharacteristicUuid) {
  void angle(double degrees) => session.notify(measurementCharacteristicUuid, steeringAngleBytes(degrees));
  return [
    EmulatedAction('Calibrate (center)', run: () {
      for (var i = 0; i < 10; i++) {
        angle(0);
      }
    }),
    EmulatedAction('Steer left (−15°)', run: () => angle(-15)),
    EmulatedAction('Center (0°)', run: () => angle(0)),
    EmulatedAction('Steer right (+15°)', run: () => angle(15)),
    EmulatedAction('Hard right (+45°)', run: () => angle(45)),
  ];
}

FakePeripheral buildEliteSterzo({String deviceId = 'emulated:sterzo'}) {
  final peripheral = FakePeripheral(
    deviceId: deviceId,
    name: 'STERZO 1337',
    advertisedServices: const [_eliteServiceUuid],
  );
  peripheral.services.addAll([
    BleService(_eliteServiceUuid, [
      bleChar(_steeringMeasurementUuid, [CharacteristicProperty.notify]),
      bleChar(_sterzoControlUuid, [CharacteristicProperty.write]),
      bleChar(_sterzoChallengeUuid, [CharacteristicProperty.indicate]),
    ]),
    ...deviceInfoServices(peripheral),
  ]);
  return peripheral;
}

/// When the app requests the challenge ([0x03, 0x10] on the control point),
/// indicate challenge 0x002A. The app's answer ([0x03, 0x11, c0, c1]) and the
/// activation ([0x02, 0x02]) are accepted without validation.
void autoRespondToSterzoChallenge(FakeUniversalBlePlatform ble, FakePeripheral peripheral) {
  peripheral.onWrite = (service, characteristic, value) {
    final isControl = characteristic.toLowerCase() == _sterzoControlUuid;
    if (isControl && value.length >= 2 && value[0] == 0x03 && value[1] == 0x10) {
      ble.notify(peripheral.deviceId, _sterzoChallengeUuid, const [0x03, 0x10, 0x00, 0x2a]);
    }
  };
}

final eliteSterzoProfile = EmulationProfile(
  name: 'Elite Sterzo',
  category: EmulationCategory.steering,
  build: buildEliteSterzo,
  onRegistered: autoRespondToSterzoChallenge,
  inputs: (session) => steeringInputs(session, _steeringMeasurementUuid),
);

/// 12-byte Square frame; the 4-byte button code sits at bytes 3-6.
List<int> squareNotification(String code8Hex) {
  assert(code8Hex.length == 8);
  final code = [
    for (var i = 0; i < 8; i += 2) int.parse(code8Hex.substring(i, i + 2), radix: 16),
  ];
  return [0x03, 0x01, 0x53, ...code, 0x03, 0x18, 0xf4, 0x01, 0x01];
}

/// Button code table from EliteSquare.BUTTON_MAPPING (elite_square.dart:84-105).
const _squareButtonCodes = <String, String>{
  'Up': '00000200',
  'Left': '00000100',
  'Down': '00000800',
  'Right': '00000400',
  'X': '00002000',
  'Square': '00001000',
  'Campagnolo left': '00008000',
  'Left brake': '00004000',
  'Left shift 1': '00000002',
  'Left shift 2': '00000001',
  'Y': '02000000',
  'A': '01000000',
  'B': '08000000',
  'Z': '04000000',
  'Circle': '20000000',
  'Triangle': '10000000',
  'Campagnolo right': '80000000',
  'Right brake': '40000000',
  'Right shift 1': '00020000',
  'Right shift 2': '00010000',
};

FakePeripheral buildEliteSquare({String deviceId = 'emulated:square'}) {
  final peripheral = FakePeripheral(
    deviceId: deviceId,
    name: 'SQUARE',
    advertisedServices: const [_eliteServiceUuid],
  );
  peripheral.services.addAll([
    BleService(_eliteServiceUuid, [
      bleChar(_squareCharacteristicUuid, [CharacteristicProperty.notify]),
    ]),
    ...deviceInfoServices(peripheral),
  ]);
  return peripheral;
}

final eliteSquareProfile = EmulationProfile(
  name: 'Elite Square',
  category: EmulationCategory.controller,
  build: buildEliteSquare,
  inputs: (session) => [
    for (final entry in _squareButtonCodes.entries)
      EmulatedButton(
        entry.key,
        onDown: () => session.notify(_squareCharacteristicUuid, squareNotification(entry.value)),
        onUp: () => session.notify(_squareCharacteristicUuid, squareNotification('00000000')),
      ),
  ],
);

FakePeripheral buildEliteRizer({String deviceId = 'emulated:rizer'}) {
  final peripheral = FakePeripheral(
    deviceId: deviceId,
    name: 'RIZER 1337',
    advertisedServices: const [_eliteServiceUuid],
  );
  peripheral.services.addAll([
    BleService(_eliteServiceUuid, [
      bleChar(_rizerWriteUuid, [CharacteristicProperty.write]),
      bleChar(_rizerStatusUuid, [CharacteristicProperty.notify]),
      bleChar(_rizerInclineUuid, [CharacteristicProperty.notify]),
      bleChar(_steeringMeasurementUuid, [CharacteristicProperty.notify]),
    ]),
    ...deviceInfoServices(peripheral),
  ]);
  return peripheral;
}

final eliteRizerProfile = EmulationProfile(
  name: 'Elite Rizer',
  category: EmulationCategory.steering,
  build: buildEliteRizer,
  inputs: (session) => steeringInputs(session, _steeringMeasurementUuid),
  decodeWrite: (characteristicUuid, value) {
    if (characteristicUuid != _rizerWriteUuid || value.length != 3 || value[0] != 0x0a) return null;
    var tenths = value[1] | (value[2] << 8);
    if (tenths >= 0x8000) tenths -= 0x10000;
    return 'Set incline ${(tenths / 10).toStringAsFixed(1)}%';
  },
);
```

Append to `all_profiles.dart` (import `elite_profiles.dart`):

```dart
      eliteSquareProfile,
      eliteSterzoProfile,
      eliteRizerProfile,
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/integration/emulation_elite_profiles_test.dart`
Expected: PASS (3 tests). Sterzo timing note: the app inserts a 1 s delay before the `[0x02, 0x02]` activation write — the steering assertions use generous `waitFor` timeouts to cover it. If the challenge-code fetch behaves differently under test, the fallback `[0x96, 0x96]` response still satisfies the `[0x03, 0x11, ...]` wait.

- [ ] **Step 5: Commit**

```bash
git add lib/bluetooth/emulation/profiles test/integration/emulation_elite_profiles_test.dart
git commit -m "feat(emulation): Elite Sterzo, Square and Rizer profiles"
```

---

### Task 9: Wahoo profiles (Kickr Bike Shift, Climb, Headwind)

Kickr Bike Shift sends 3-byte button frames (`prefix16 | pressedFlag+seq`). Climb and Headwind are accessory sinks verified through the decoded write log; Headwind additionally echoes a status frame so the app's mode tracking behaves like real hardware.

**Files:**
- Create: `lib/bluetooth/emulation/profiles/wahoo_profiles.dart`
- Modify: `lib/bluetooth/emulation/profiles/all_profiles.dart`
- Test: `test/integration/emulation_wahoo_profiles_test.dart`

**Interfaces:**
- Consumes: harness helpers (Task 1), `EmulationSession` (Task 3).
- Produces: profiles `wahooKickrBikeShiftProfile`, `wahooKickrClimbProfile`, `wahooKickrHeadwindProfile`.

- [ ] **Step 1: Write the failing test**

Create `test/integration/emulation_wahoo_profiles_test.dart`:

```dart
import 'package:bike_control/bluetooth/devices/wahoo/wahoo_kickr_bike_shift.dart';
import 'package:bike_control/bluetooth/devices/wahoo/wahoo_kickr_climb.dart';
import 'package:bike_control/bluetooth/devices/wahoo/wahoo_kickr_headwind.dart';
import 'package:bike_control/bluetooth/emulation/emulation_profile.dart';
import 'package:bike_control/bluetooth/emulation/profiles/wahoo_profiles.dart';
import 'package:bike_control/utils/actions/base_actions.dart';
import 'package:bike_control/utils/core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'harness/test_env.dart';

Future<void> main() async {
  final env = await IntegrationEnv.setUp();
  late StubActions stubActions;

  core.connection.initialize();

  setUp(() async {
    await env.resetState();
    stubActions = StubActions();
    core.actionHandler = stubActions;
    core.emulation.reset();
    core.emulation.attach(env.ble);
  });

  tearDown(() async {
    await env.resetConnection();
  });

  Future<T> connect<T extends Object>(EmulationProfile profile) async {
    core.emulation.start(profile);
    await core.connection.performScanning();
    await IntegrationEnv.waitFor(
      () => core.connection.devices.whereType<T>().isNotEmpty,
      description: '$T detected',
    );
    return core.connection.devices.whereType<T>().first;
  }

  test('Kickr Bike Shift: shift-up-right press performs shiftUpRight', () async {
    await connect<WahooKickrBikeShift>(wahooKickrBikeShiftProfile);
    final session = core.emulation.sessionFor('emulated:kickr-bike-shift')!;

    final button = session.inputs.whereType<EmulatedButton>().firstWhere((b) => b.label == 'Shift up right');
    button.onDown();
    button.onUp();

    await IntegrationEnv.waitFor(() => stubActions.performedActions.isNotEmpty, description: 'shift action');
    expect(
      stubActions.performedActions.map((a) => a.button),
      contains(WahooKickrShiftButtons.shiftUpRight),
    );
  });

  test('Climb: requests control on connect and logs incline writes', () async {
    final device = await connect<WahooKickrClimb>(wahooKickrClimbProfile);
    final session = core.emulation.sessionFor('emulated:kickr-climb')!;

    await IntegrationEnv.waitFor(
      () => session.peripheral.writes.any((w) => w.value.length == 1 && w.value[0] == 0x67),
      description: 'request-control write',
    );

    await device.writeInclineRaw(500); // +5.00% → [0x66, 0xF4, 0x01]
    await IntegrationEnv.waitFor(
      () => session.peripheral.writes.any(
        (w) => w.value.length == 3 && w.value[0] == 0x66 && w.value[1] == 0xf4 && w.value[2] == 0x01,
      ),
      description: 'incline write',
    );
    expect(session.writeLog.value, contains('Set incline 5.0%'));
  });

  test('Headwind: setSpeed writes manual mode then the speed, both logged', () async {
    final device = await connect<WahooKickrHeadwind>(wahooKickrHeadwindProfile);
    final session = core.emulation.sessionFor('emulated:kickr-headwind')!;

    await device.setSpeed(50);

    await IntegrationEnv.waitFor(
      () => session.peripheral.writes.any((w) => w.value.length == 2 && w.value[0] == 0x02 && w.value[1] == 50),
      description: 'fan speed write',
    );
    expect(session.writeLog.value, contains('Manual mode'));
    expect(session.writeLog.value, contains('Fan speed 50%'));
  });
}
```

Method signatures to verify while writing: `WahooKickrClimb.writeInclineRaw` (`wahoo_kickr_climb.dart:47-56`) and `WahooKickrHeadwind.setSpeed` (`wahoo_kickr_headwind.dart:62-100`) — drop/add `await` to match their return types. Button constants: `WahooKickrShiftButtons` (`wahoo_kickr_bike_shift.dart:131-186`).

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/integration/emulation_wahoo_profiles_test.dart`
Expected: FAIL — `wahoo_profiles.dart` does not exist.

- [ ] **Step 3: Implement**

Create `lib/bluetooth/emulation/profiles/wahoo_profiles.dart`:

```dart
import 'package:prop/utils/wahoo_climb.dart';
import 'package:universal_ble/universal_ble.dart';

import '../emulated_ble_platform.dart';
import '../emulated_peripherals.dart';
import '../emulation_profile.dart';

// Kickr Bike Shift (detection is by NAME, no advertised service needed).
const _kickrShiftServiceUuid = 'a026ee0d-0a7d-4ab3-97fa-f1500f9feb8b';
const _kickrShiftCharacteristicUuid = 'a026e03c-0a7d-4ab3-97fa-f1500f9feb8b';

// Headwind.
const _headwindServiceUuid = 'a026ee0c-0a7d-4ab3-97fa-f1500f9feb8b';
const _headwindCharacteristicUuid = 'a026e038-0a7d-4ab3-97fa-f1500f9feb8b';

/// Button prefixes from WahooKickrBikeShift.prefixToButton
/// (wahoo_kickr_bike_shift.dart:115-128).
const _kickrShiftButtons = <String, int>{
  'Right up': 0x0001,
  'Right down': 0x8000,
  'Right steer': 0x0008,
  'Left up': 0x0200,
  'Left down': 0x0400,
  'Left steer': 0x2000,
  'Shift up right': 0x0004,
  'Shift down right': 0x0002,
  'Shift up left': 0x1000,
  'Shift down left': 0x0800,
  'Right brake': 0x4000,
  'Left brake': 0x0100,
};

int _kickrSeq = 0;

/// 3-byte Kickr Bike Shift frame: 16-bit button prefix, then a byte whose MSB
/// is the pressed flag and whose low 7 bits are a rolling dedupe sequence.
List<int> kickrBikeShiftFrame(int prefix, {required bool pressed}) {
  _kickrSeq = (_kickrSeq + 1) & 0x7f;
  return [(prefix >> 8) & 0xff, prefix & 0xff, (pressed ? 0x80 : 0x00) | _kickrSeq];
}

final wahooKickrBikeShiftProfile = EmulationProfile(
  name: 'Wahoo Kickr Bike Shift',
  category: EmulationCategory.controller,
  build: () {
    final peripheral = FakePeripheral(deviceId: 'emulated:kickr-bike-shift', name: 'KICKR BIKE SHIFT 1337');
    peripheral.services.addAll([
      BleService(_kickrShiftServiceUuid, [
        bleChar(_kickrShiftCharacteristicUuid, [CharacteristicProperty.notify]),
      ]),
      ...deviceInfoServices(peripheral),
    ]);
    return peripheral;
  },
  inputs: (session) => [
    for (final entry in _kickrShiftButtons.entries)
      EmulatedButton(
        entry.key,
        onDown: () =>
            session.notify(_kickrShiftCharacteristicUuid, kickrBikeShiftFrame(entry.value, pressed: true)),
        onUp: () =>
            session.notify(_kickrShiftCharacteristicUuid, kickrBikeShiftFrame(entry.value, pressed: false)),
      ),
  ],
);

final wahooKickrClimbProfile = EmulationProfile(
  name: 'Wahoo Kickr Climb',
  category: EmulationCategory.accessory,
  build: () {
    final peripheral = FakePeripheral(
      deviceId: 'emulated:kickr-climb',
      name: 'KICKR CLIMB 1337',
      advertisedServices: [lcUuid(wahooClimbServiceUuid)],
    );
    peripheral.services.addAll([
      BleService(lcUuid(wahooClimbServiceUuid), [
        bleChar(wahooClimbCharacteristicUuid, [
          CharacteristicProperty.notify,
          CharacteristicProperty.write,
          CharacteristicProperty.writeWithoutResponse,
        ]),
      ]),
      ...deviceInfoServices(peripheral),
    ]);
    return peripheral;
  },
  decodeWrite: (characteristicUuid, value) {
    if (characteristicUuid != lcUuid(wahooClimbCharacteristicUuid)) return null;
    if (value.length == 1 && value[0] == wahooClimbRequestControlOpcode) return 'Request control';
    if (value.length == 3 && value[0] == wahooClimbSetInclineOpcode) {
      var grade001 = value[1] | (value[2] << 8);
      if (grade001 >= 0x8000) grade001 -= 0x10000;
      return 'Set incline ${(grade001 / 100).toStringAsFixed(1)}%';
    }
    return null;
  },
);

final wahooKickrHeadwindProfile = EmulationProfile(
  name: 'Wahoo Kickr Headwind',
  category: EmulationCategory.accessory,
  build: () {
    final peripheral = FakePeripheral(
      deviceId: 'emulated:kickr-headwind',
      name: 'HEADWIND 1337',
      advertisedServices: const [_headwindServiceUuid],
    );
    peripheral.services.addAll([
      BleService(_headwindServiceUuid, [
        bleChar(_headwindCharacteristicUuid, [
          CharacteristicProperty.notify,
          CharacteristicProperty.write,
          CharacteristicProperty.writeWithoutResponse,
        ]),
      ]),
      ...deviceInfoServices(peripheral),
    ]);
    return peripheral;
  },
  // Echo a status frame [0xFD, 0x01, speed, mode] so the app's mode tracking
  // behaves like the real fan (otherwise it re-sends manual mode every time).
  onRegistered: (ble, peripheral) {
    var speed = 0;
    peripheral.onWrite = (service, characteristic, value) {
      if (characteristic.toLowerCase() != _headwindCharacteristicUuid || value.length < 2) return;
      if (value[0] == 0x02) {
        speed = value[1];
        ble.notify(peripheral.deviceId, _headwindCharacteristicUuid, [0xfd, 0x01, speed, 0x04]);
      } else if (value[0] == 0x04) {
        ble.notify(peripheral.deviceId, _headwindCharacteristicUuid, [0xfd, 0x01, speed, value[1]]);
      }
    };
  },
  decodeWrite: (characteristicUuid, value) {
    if (characteristicUuid != _headwindCharacteristicUuid || value.length < 2) return null;
    if (value[0] == 0x04 && value[1] == 0x04) return 'Manual mode';
    if (value[0] == 0x04 && value[1] == 0x02) return 'Heart-rate mode';
    if (value[0] == 0x02) return 'Fan speed ${value[1]}%';
    return null;
  },
);
```

`wahooClimbCharacteristicUuid`, `wahooClimbServiceUuid`, `wahooClimbRequestControlOpcode` (0x67), `wahooClimbSetInclineOpcode` (0x66) all come from `package:prop/utils/wahoo_climb.dart`.

Append to `all_profiles.dart` (import `wahoo_profiles.dart`):

```dart
      wahooKickrBikeShiftProfile,
      wahooKickrClimbProfile,
      wahooKickrHeadwindProfile,
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/integration/emulation_wahoo_profiles_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/bluetooth/emulation/profiles test/integration/emulation_wahoo_profiles_test.dart
git commit -m "feat(emulation): Wahoo Kickr Bike Shift, Climb and Headwind profiles"
```

---

### Task 10: Misc profiles (Cycplus BC2, ThinkRider VS200, SRAM AXS, OpenBikeControl, Shimano Di2)

**Files:**
- Create: `lib/bluetooth/emulation/profiles/misc_profiles.dart`
- Modify: `lib/bluetooth/emulation/profiles/all_profiles.dart`
- Test: `test/integration/emulation_misc_profiles_test.dart`

**Interfaces:**
- Consumes: harness helpers (Task 1), `buildShimanoDi2` (Task 1), `EmulationSession` (Task 3).
- Produces: profiles `cycplusBc2Profile`, `thinkRiderVs200Profile`, `sramAxsProfile`, `openBikeControlProfile`, `shimanoDi2Profile`.

- [ ] **Step 1: Write the failing test**

Create `test/integration/emulation_misc_profiles_test.dart`:

```dart
import 'package:bike_control/bluetooth/devices/cycplus/cycplus_bc2.dart';
import 'package:bike_control/bluetooth/devices/openbikecontrol/openbikecontrol_device.dart';
import 'package:bike_control/bluetooth/devices/shimano/shimano_di2.dart';
import 'package:bike_control/bluetooth/devices/sram/sram_axs.dart';
import 'package:bike_control/bluetooth/devices/thinkrider/thinkrider_vs200.dart';
import 'package:bike_control/bluetooth/emulation/emulation_profile.dart';
import 'package:bike_control/bluetooth/emulation/profiles/misc_profiles.dart';
import 'package:bike_control/utils/actions/base_actions.dart';
import 'package:bike_control/utils/core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'harness/test_env.dart';

Future<void> main() async {
  final env = await IntegrationEnv.setUp();
  late StubActions stubActions;

  core.connection.initialize();

  setUp(() async {
    await env.resetState();
    stubActions = StubActions();
    core.actionHandler = stubActions;
    core.emulation.reset();
    core.emulation.attach(env.ble);
  });

  tearDown(() async {
    await env.resetConnection();
  });

  Future<void> connect<T extends Object>(EmulationProfile profile) async {
    core.emulation.start(profile);
    await core.connection.performScanning();
    await IntegrationEnv.waitFor(
      () => core.connection.devices.whereType<T>().isNotEmpty,
      description: '$T detected',
    );
  }

  test('Cycplus BC2: shift-up press performs shiftUp', () async {
    await connect<CycplusBc2>(cycplusBc2Profile);
    final session = core.emulation.sessionFor('emulated:cycplus-bc2')!;

    final up = session.inputs.whereType<EmulatedButton>().firstWhere((b) => b.label == 'Shift up');
    up.onDown();
    up.onUp();

    await IntegrationEnv.waitFor(() => stubActions.performedActions.isNotEmpty, description: 'cycplus action');
    expect(stubActions.performedActions.map((a) => a.button), contains(CycplusBc2Buttons.shiftUp));
  });

  test('ThinkRider VS200: shift-up pattern performs one click', () async {
    await connect<ThinkRiderVs200>(thinkRiderVs200Profile);
    final session = core.emulation.sessionFor('emulated:thinkrider-vs200')!;

    session.inputs.whereType<EmulatedAction>().firstWhere((a) => a.label == 'Shift up').run();

    await IntegrationEnv.waitFor(() => stubActions.performedActions.isNotEmpty, description: 'thinkrider action');
    expect(stubActions.performedActions.map((a) => a.button), contains(ThinkRiderVs200Buttons.shiftUp));
  });

  test('SRAM AXS: a single tap performs the SRAM Tap button', () async {
    await connect<SramAxs>(sramAxsProfile);
    final session = core.emulation.sessionFor('emulated:sram-axs')!;

    session.inputs.whereType<EmulatedAction>().firstWhere((a) => a.label == 'Tap').run();

    // The tap fires after the double-click window (up to 600 ms) elapses.
    await IntegrationEnv.waitFor(
      () => stubActions.performedActions.isNotEmpty,
      timeout: const Duration(seconds: 3),
      description: 'sram tap action',
    );
    expect(stubActions.performedActions.map((a) => a.button.name), contains('SRAM Tap'));
  });

  test('OpenBikeControl: Shift Up press performs the Shift Up button', () async {
    await connect<OpenBikeControlDevice>(openBikeControlProfile);
    final session = core.emulation.sessionFor('emulated:openbikecontrol')!;

    // The app writes its app-info to the peripheral during handleServices.
    await IntegrationEnv.waitFor(
      () => session.peripheral.writes.isNotEmpty,
      description: 'app-info write',
    );

    final up = session.inputs.whereType<EmulatedButton>().firstWhere((b) => b.label == 'Shift Up');
    up.onDown();
    up.onUp();

    await IntegrationEnv.waitFor(() => stubActions.performedActions.isNotEmpty, description: 'obc action');
    expect(stubActions.performedActions.map((a) => a.button.name), contains('Shift Up'));
  });

  test('Shimano Di2: channel 1 press performs the D-Fly Channel 1 button', () async {
    await connect<ShimanoDi2>(shimanoDi2Profile);
    final session = core.emulation.sessionFor('emulated:di2')!;

    final channel1 = session.inputs.whereType<EmulatedButton>().firstWhere((b) => b.label == 'D-Fly Channel 1');
    channel1.onDown();
    channel1.onUp();

    await IntegrationEnv.waitFor(() => stubActions.performedActions.isNotEmpty, description: 'di2 action');
    expect(stubActions.performedActions.map((a) => a.button.name), contains('D-Fly Channel 1'));
  });
}
```

Button-constant caveats: `CycplusBc2Buttons` (`cycplus_bc2.dart:89-108`) and `ThinkRiderVs200Buttons` (`thinkrider_vs200.dart:89-108`) are static classes; SRAM/OBC/Di2 buttons are created dynamically via `getOrAddButton`, so those tests compare `button.name` strings.

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/integration/emulation_misc_profiles_test.dart`
Expected: FAIL — `misc_profiles.dart` does not exist.

- [ ] **Step 3: Implement**

Create `lib/bluetooth/emulation/profiles/misc_profiles.dart`:

```dart
import 'dart:async';

import 'package:universal_ble/universal_ble.dart';

import '../emulated_ble_platform.dart';
import '../emulated_peripherals.dart';
import '../emulation_profile.dart';

// Cycplus BC2 — Nordic UART service.
const _cycplusServiceUuid = '6e400001-b5a3-f393-e0a9-e50e24dcca9e';
const _cycplusTxUuid = '6e400003-b5a3-f393-e0a9-e50e24dcca9e';
const _cycplusRxUuid = '6e400002-b5a3-f393-e0a9-e50e24dcca9e';

/// 8-byte CYCPLUS frame: byte 6 = shift-up state, byte 7 = shift-down state,
/// 0x01 = pressed (idle observed as 0x03 in real captures).
List<int> cycplusFrame({required bool upPressed, required bool downPressed}) =>
    [0xfe, 0xef, 0xff, 0xee, 0x02, 0x06, upPressed ? 0x01 : 0x03, downPressed ? 0x01 : 0x03];

final cycplusBc2Profile = EmulationProfile(
  name: 'Cycplus BC2',
  category: EmulationCategory.controller,
  build: () {
    final peripheral = FakePeripheral(deviceId: 'emulated:cycplus-bc2', name: 'CYCPLUS BC2');
    peripheral.services.addAll([
      BleService(_cycplusServiceUuid, [
        bleChar(_cycplusTxUuid, [CharacteristicProperty.notify]),
        bleChar(_cycplusRxUuid, [CharacteristicProperty.write, CharacteristicProperty.writeWithoutResponse]),
      ]),
      ...deviceInfoServices(peripheral),
    ]);
    return peripheral;
  },
  inputs: (session) => [
    EmulatedButton(
      'Shift up',
      onDown: () => session.notify(_cycplusTxUuid, cycplusFrame(upPressed: true, downPressed: false)),
      onUp: () => session.notify(_cycplusTxUuid, cycplusFrame(upPressed: false, downPressed: false)),
    ),
    EmulatedButton(
      'Shift down',
      onDown: () => session.notify(_cycplusTxUuid, cycplusFrame(upPressed: false, downPressed: true)),
      onUp: () => session.notify(_cycplusTxUuid, cycplusFrame(upPressed: false, downPressed: false)),
    ),
  ],
);

// ThinkRider VS200 — fixed 5-byte patterns, self-releasing (device clicks).
const _thinkRiderServiceUuid = '0000fea0-0000-1000-8000-00805f9b34fb';
const _thinkRiderCharacteristicUuid = '0000fea1-0000-1000-8000-00805f9b34fb';

final thinkRiderVs200Profile = EmulationProfile(
  name: 'ThinkRider VS200',
  category: EmulationCategory.controller,
  build: () {
    final peripheral = FakePeripheral(deviceId: 'emulated:thinkrider-vs200', name: 'THINK VS01-0000285');
    peripheral.services.addAll([
      BleService(_thinkRiderServiceUuid, [
        bleChar(_thinkRiderCharacteristicUuid, [CharacteristicProperty.notify]),
      ]),
      ...deviceInfoServices(peripheral),
    ]);
    return peripheral;
  },
  inputs: (session) => [
    EmulatedAction(
      'Shift up',
      run: () => session.notify(_thinkRiderCharacteristicUuid, const [0xf3, 0x05, 0x03, 0x01, 0xfc]),
    ),
    EmulatedAction(
      'Shift down',
      run: () => session.notify(_thinkRiderCharacteristicUuid, const [0xf3, 0x05, 0x03, 0x00, 0xfb]),
    ),
  ],
);

// SRAM AXS — detected by advertised fe51; subscribed on the d905… trigger.
// Any notification counts as a tap; two taps within the window = double tap.
const _sramAdvertisedServiceUuid = '0000fe51-0000-1000-8000-00805f9b34fb';
const _sramRelevantServiceUuid = 'd9050053-90aa-4c7c-b036-1e01fb8eb7ee';
const _sramTriggerUuid = 'd9050054-90aa-4c7c-b036-1e01fb8eb7ee';

final sramAxsProfile = EmulationProfile(
  name: 'SRAM AXS',
  category: EmulationCategory.controller,
  build: () {
    final peripheral = FakePeripheral(
      deviceId: 'emulated:sram-axs',
      name: 'SRAM AXS',
      advertisedServices: const [_sramAdvertisedServiceUuid],
    );
    peripheral.services.addAll([
      BleService(_sramRelevantServiceUuid, [
        bleChar(_sramTriggerUuid, [CharacteristicProperty.notify]),
      ]),
      ...deviceInfoServices(peripheral),
    ]);
    return peripheral;
  },
  inputs: (session) => [
    EmulatedAction('Tap', run: () => session.notify(_sramTriggerUuid, const [0x01])),
    EmulatedAction('Double tap', run: () {
      session.notify(_sramTriggerUuid, const [0x01]);
      unawaited(
        Future<void>.delayed(
          const Duration(milliseconds: 100),
          () => session.notify(_sramTriggerUuid, const [0x01]),
        ),
      );
    }),
  ],
);

// OpenBikeControl — button-state notify + haptic/app-info write chars.
const _obcServiceUuid = 'd273f680-d548-419d-b9d1-fa0472345229';
const _obcButtonStateUuid = 'd273f681-d548-419d-b9d1-fa0472345229';
const _obcHapticUuid = 'd273f682-d548-419d-b9d1-fa0472345229';
const _obcAppInfoUuid = 'd273f683-d548-419d-b9d1-fa0472345229';

/// Button IDs from OpenBikeProtocolParser.BUTTON_NAMES (protocol_parser.dart:26-70).
const _obcButtons = <String, int>{
  'Shift Up': 0x01,
  'Shift Down': 0x02,
  'Up': 0x10,
  'Down': 0x11,
  'Select': 0x14,
  'Back': 0x15,
  'Menu': 0x16,
  'Home': 0x17,
  'Steer Left': 0x18,
  'Steer Right': 0x19,
};

final openBikeControlProfile = EmulationProfile(
  name: 'OpenBikeControl',
  category: EmulationCategory.controller,
  build: () {
    final peripheral = FakePeripheral(
      deviceId: 'emulated:openbikecontrol',
      name: 'OpenBike',
      advertisedServices: const [_obcServiceUuid],
    );
    peripheral.services.addAll([
      BleService(_obcServiceUuid, [
        bleChar(_obcButtonStateUuid, [CharacteristicProperty.notify]),
        bleChar(_obcHapticUuid, [CharacteristicProperty.write, CharacteristicProperty.writeWithoutResponse]),
        bleChar(_obcAppInfoUuid, [CharacteristicProperty.write, CharacteristicProperty.writeWithoutResponse]),
      ]),
      ...deviceInfoServices(peripheral),
    ]);
    return peripheral;
  },
  inputs: (session) => [
    for (final entry in _obcButtons.entries)
      EmulatedButton(
        entry.key,
        // [msgType 0x01, buttonId, state] — state 1 = pressed, 0 = released.
        onDown: () => session.notify(_obcButtonStateUuid, [0x01, entry.value, 0x01]),
        onUp: () => session.notify(_obcButtonStateUuid, [0x01, entry.value, 0x00]),
      ),
  ],
);

// Shimano Di2 — D-Fly channel bitmasks over indications; the first frame only
// initializes the app-side state, so a baseline precedes the first press.
const _di2DFlyChannelUuid = '00002ac2-5348-494d-414e-4f5f424c4500';

final shimanoDi2Profile = EmulationProfile(
  name: 'Shimano Di2',
  category: EmulationCategory.controller,
  build: () => buildShimanoDi2(deviceId: 'emulated:di2'),
  inputs: (session) {
    var initialized = false;
    void send(List<int> channels) => session.notify(_di2DFlyChannelUuid, [0x00, ...channels]);
    List<int> single(int index, int value) => [for (var i = 0; i < 3; i++) i == index ? value : 0x00];
    void ensureBaseline() {
      if (initialized) return;
      send(const [0x00, 0x00, 0x00]);
      initialized = true;
    }

    return [
      for (var channel = 0; channel < 3; channel++)
        EmulatedButton(
          'D-Fly Channel ${channel + 1}',
          onDown: () {
            ensureBaseline();
            send(single(channel, 0x10)); // 0x10 = short press
          },
          onUp: () => send(single(channel, 0x00)),
        ),
    ];
  },
);
```

Update `all_profiles.dart` to its final form:

```dart
import '../emulation_profile.dart';
import 'elite_profiles.dart';
import 'misc_profiles.dart';
import 'wahoo_profiles.dart';
import 'zwift_profiles.dart';

/// Every device the debug "Emulate device" menu can add: controllers first,
/// then steering, then accessories.
List<EmulationProfile> get allEmulationProfiles => [
      zwiftClickProfile,
      zwiftClickV2LeftProfile,
      zwiftClickV2RightProfile,
      zwiftPlayLeftProfile,
      zwiftPlayRightProfile,
      zwiftPlayFw2Profile,
      zwiftRideProfile,
      eliteSquareProfile,
      wahooKickrBikeShiftProfile,
      cycplusBc2Profile,
      thinkRiderVs200Profile,
      sramAxsProfile,
      openBikeControlProfile,
      shimanoDi2Profile,
      eliteSterzoProfile,
      eliteRizerProfile,
      wahooKickrClimbProfile,
      wahooKickrHeadwindProfile,
    ];
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/integration/emulation_misc_profiles_test.dart`
Expected: PASS (5 tests). SRAM note: `SramAxs` sets `isBeta: true` and its double-click window comes from settings (`SramAxsDoubleClickWindowMs`); the single-tap test waits generously. Di2 note: if the `getOrAddButton` name differs (it may be created only after the first press), assert on `stubActions.performedActions` after the press as written — the button is added during processing.

- [ ] **Step 5: Commit**

```bash
git add lib/bluetooth/emulation/profiles test/integration/emulation_misc_profiles_test.dart
git commit -m "feat(emulation): Cycplus, ThinkRider, SRAM AXS, OpenBikeControl and Di2 profiles"
```

---

### Task 11: Final verification

**Files:** none new.

- [ ] **Step 1: Full static + test pass**

Run: `flutter analyze`
Expected: clean.
Run: `flutter test`
Expected: full suite PASS (pre-existing skips stay skipped).

- [ ] **Step 2: Grep for stragglers**

Run: `grep -rn "harness/fake_ble_platform\|harness/fake_peripherals" lib test`
Expected: no matches (all imports point at `lib/bluetooth/emulation/`).

- [ ] **Step 3: Manual QA checklist (desktop debug build)**

`flutter run -d macos`, then:
1. Menu → Emulate device → Zwift Click: device appears, connects, battery/FW shown.
2. Device page → Emulation card: press-and-hold "Shift Up (+)" ≥ 600 ms — long-press behavior (repeat or mapped long-press action) fires; short press fires single click.
3. Emulate a second device (Elite Sterzo) alongside: both connected simultaneously; Calibrate then Steer right shows steering actions in the activity log.
4. Emulate Wahoo Kickr Climb: Emulation card write log shows "Request control" and incline writes when the incline actions/pipeline run.
5. "Drop connection": device grays out, reconnects automatically via the scan.
6. Forget the emulated device via the existing device actions: it disappears; re-adding the same profile from the menu works.
7. With a real controller nearby (if available): real device still detects and works — routing pass-through unaffected.

- [ ] **Step 4: Update the spec status + commit**

In `docs/superpowers/specs/2026-07-02-controller-emulation-design.md` change `**Status:** Approved` to `**Status:** Implemented`.

```bash
git add -f docs/superpowers/specs/2026-07-02-controller-emulation-design.md
git commit -m "docs: mark controller emulation spec implemented"
```

