import 'dart:typed_data';

import 'package:bike_control/bluetooth/devices/zwift/ftms_mdns_emulator.dart';
import 'package:bike_control/bluetooth/devices/zwift/zwift_clickv2.dart' show ftmsEmulator;
import 'package:bike_control/gen/l10n.dart';
import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_test/flutter_test.dart';
import 'package:prop/emulators/ble_definition.dart';
import 'package:universal_ble/universal_ble.dart';

/// Minimal stand-in for a trainer bridge definition — enough to occupy a second
/// slot in the shared composite alongside the network controller's definition.
class _BridgeStubDef extends BleDefinition {
  @override
  List<String> get serviceUUIDs => ['00001826-0000-1000-8000-00805f9b34fb'];

  @override
  List<String> get advertiseServiceUUIDs => serviceUUIDs;

  @override
  List<BleCharacteristic> getCharacteristics(String svc) => const [];

  @override
  void onWriteRequest(String c, List<int> d) {}

  @override
  void onNotification(String c, Uint8List bytes) {}
}

void main() {
  setUpAll(() async {
    await AppLocalizations.load(const Locale('en'));
  });

  test('stop() detaches its own definition even when a bridge definition stays attached', () async {
    final emulator = FtmsMdnsEmulator();
    final bridge = _BridgeStubDef();

    // Both a trainer bridge's definition and the network controller's own
    // definition share the ftmsEmulator composite.
    await ftmsEmulator.attachDefinition(bridge);
    await ftmsEmulator.attachDefinition(emulator.def);
    addTearDown(() async {
      await ftmsEmulator.detachDefinition(bridge);
      await ftmsEmulator.detachDefinition(emulator.def);
    });

    expect(ftmsEmulator.composite.children, containsAll(<BleDefinition>[bridge, emulator.def]));

    emulator.stop();

    // Stopping the controller must take its definition off the shared endpoint,
    // while the bridge's own definition stays.
    expect(ftmsEmulator.composite.children, contains(bridge));
    expect(ftmsEmulator.composite.children, isNot(contains(emulator.def)));
  });
}
