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

  test('writeLog caps retained entries at 100, keeping the most recent', () async {
    final profile = EmulationProfile(
      name: 'Sink',
      category: EmulationCategory.accessory,
      build: () => FakePeripheral(deviceId: 'emulated:sink', name: 'Sink'),
      decodeWrite: (characteristicUuid, value) => 'wrote ${value.first}',
    );
    final session = manager.start(profile);

    for (var i = 0; i < 120; i++) {
      await ble.writeValue(
        'emulated:sink',
        'service',
        'char',
        Uint8List.fromList([i]),
        BleOutputProperty.withResponse,
      );
    }

    expect(session.writeLog.value.length, 100);
    expect(session.writeLog.value.last, 'wrote 119');
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
