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
