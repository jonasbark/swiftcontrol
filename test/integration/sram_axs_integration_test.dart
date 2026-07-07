import 'dart:typed_data';

import 'package:bike_control/bluetooth/devices/sram/sram_axs.dart' show SramAxs, SramAxsConstants;
import 'package:bike_control/utils/actions/base_actions.dart';
import 'package:bike_control/utils/core.dart';
import 'package:bike_control/utils/keymap/apps/zwift.dart';
import 'package:bike_control/utils/keymap/keymap.dart';
// The crypto/protobuf/bond helpers that drive the fake derailleur's handshake
// and reaction-config bookkeeping are NOT re-exported by package:prop/prop.dart
// (only SramAxsLogic, SramTransport, SramReactionTrigger and the SramAxs
// constants class are) — they must be imported directly from their files.
import 'package:prop/devices/sram/sram_axs_bond.dart';
import 'package:prop/devices/sram/sram_axs_crypto.dart';
import 'package:prop/devices/sram/sram_axs_protobuf.dart';
// prop.dart exports a `SramAxs` *constants* class that collides with the app's
// `SramAxs` *device* class (imported above) — bring it in under a prefix.
import 'package:prop/prop.dart' as prop;
import 'package:flutter_test/flutter_test.dart';
import 'package:universal_ble/universal_ble.dart';

import 'harness/fake_ble_platform.dart';
import 'harness/test_env.dart';

const String _uuidBase = '-90aa-4c7c-b036-1e01fb8eb7ee';
const String _controlServiceUuid = 'd9050050$_uuidBase';
const String _reactionChar1 = 'd9050028$_uuidBase';
const String _reactionChar2 = 'd9050029$_uuidBase';

String _lc(String uuid) => uuid.toLowerCase();

BleCharacteristic _char(String uuid, List<CharacteristicProperty> properties) =>
    BleCharacteristic(_lc(uuid), properties, []);

/// A scripted fake SRAM AXS derailleur: answers the `srambond` V1
/// Diffie-Hellman handshake, stores/validates reaction-config writes (with
/// anti-replay token bookkeeping), and can emit an encrypted button press
/// (componentEvent + control-trigger notify pair) like the real device.
class FakeSramDerailleur {
  FakeSramDerailleur(this.env, {String deviceId = 'fake-sram-axs', String name = 'SRAM Rival AXS'})
      : peripheral = FakePeripheral(
          deviceId: deviceId,
          name: name,
          advertisedServices: [_lc(SramAxsConstants.SERVICE_UUID)],
        ) {
    peripheral.services.addAll([
      BleService(_lc(prop.SramAxs.bondService), [
        _char(prop.SramAxs.bondChar, [CharacteristicProperty.write, CharacteristicProperty.notify]),
        _char(prop.SramAxs.tokenChar, [CharacteristicProperty.read]),
      ]),
      BleService(_lc(_controlServiceUuid), [
        _char(prop.SramAxs.controlTriggerChar, [CharacteristicProperty.read, CharacteristicProperty.notify]),
        _char(prop.SramAxs.componentEventChar, [CharacteristicProperty.notify]),
        _char(_reactionChar1, [CharacteristicProperty.read, CharacteristicProperty.write]),
        _char(_reactionChar2, [CharacteristicProperty.read, CharacteristicProperty.write]),
      ]),
    ]);

    // Seed both reaction slots with an assigned trigger (device_type 0,
    // button_mask 1) so setupControl()'s backup/unassign pass has something
    // real to read, back up and clear.
    peripheral.readValues[_lc(_reactionChar1)] =
        SramEax.encrypt(sessionKey, SramProtobuf.encodeReactionConfig(const [0], const [1], 0), SramEax.randomNonce());
    peripheral.readValues[_lc(_reactionChar2)] =
        SramEax.encrypt(sessionKey, SramProtobuf.encodeReactionConfig(const [0], const [1], 0), SramEax.randomNonce());
    peripheral.readValues[_lc(prop.SramAxs.tokenChar)] = _encodeToken(currentToken);

    peripheral.onWrite = _onWrite;
  }

  final IntegrationEnv env;
  final FakePeripheral peripheral;

  /// Fixed 16-byte AES-EAX session key the bond handshake hands back to the app.
  final Uint8List sessionKey = Uint8List.fromList(List<int>.generate(16, (i) => i + 1));

  /// Fixed DH private exponent for the derailleur side of the handshake.
  final BigInt devicePrivate = BigInt.parse('7f3a91c04d2e88b6', radix: 16);

  int currentToken = 0;

  /// Set true the first time a reaction char is written with an empty
  /// trigger (device_types/button_masks both cleared) — i.e. the derailleur
  /// got unassigned by disableShifting().
  bool derailleurUnassigned = false;

  String get deviceId => peripheral.deviceId;

  Uint8List _encodeToken(int token) =>
      SramEax.encrypt(sessionKey, SramProtobuf.encodeReactionConfig(const [], const [], token), SramEax.randomNonce());

  void _onWrite(String service, String characteristic, Uint8List value) {
    final lc = characteristic.toLowerCase();
    if (lc == _lc(prop.SramAxs.bondChar)) {
      _handleBondWrite(value);
    } else if (lc == _lc(_reactionChar1) || lc == _lc(_reactionChar2)) {
      _handleReactionWrite(lc, value);
    }
  }

  void _handleBondWrite(Uint8List value) {
    if (value.length == 16 && value[0] == 0 && value[1] == 1) {
      // Step 1: init token -> answer with our DH public key B = g^devicePrivate mod N.
      final devicePublic = SramBond.bigIntTo16(BigInt.from(prop.SramAxs.dhG).modPow(devicePrivate, prop.SramAxs.dhN));
      env.ble.notify(peripheral.deviceId, prop.SramAxs.bondChar, devicePublic);
    } else if (value.length == 16) {
      // Step 2: the app's ephemeral public key A -> derive the shared secret
      // and hand back the create-bond frame (sessionKey encrypted under it).
      final appPublic = SramBond.bigIntFrom(value);
      final secret = SramBond.bigIntTo16(appPublic.modPow(devicePrivate, prop.SramAxs.dhN));
      final frame = SramEax.encrypt(secret, sessionKey, SramEax.randomNonce());
      env.ble.notify(peripheral.deviceId, prop.SramAxs.bondChar, frame);
    }
    // else: the 1-byte 0x73 ack — nothing to answer.
  }

  void _handleReactionWrite(String charLc, Uint8List value) {
    final pt = SramEax.decrypt(sessionKey, value);
    if (pt == null) return; // wrong key — shouldn't happen once bonded.
    final fields = SramProtobuf.parseVarints(pt);
    if (fields[prop.SramAxs.fieldToken] != currentToken) return; // stale/replayed token — reject.
    final (dts, masks) = SramProtobuf.parseReactionConfig(pt);
    if (dts.isEmpty && masks.isEmpty) derailleurUnassigned = true;
    currentToken++;
    peripheral.readValues[charLc] =
        SramEax.encrypt(sessionKey, SramProtobuf.encodeReactionConfig(dts, masks, currentToken), SramEax.randomNonce());
    peripheral.readValues[_lc(prop.SramAxs.tokenChar)] = _encodeToken(currentToken);
  }

  /// Simulate a shift-paddle press from controller [serial]: a plaintext
  /// componentEvent identifying the pressing controller, then an encrypted
  /// control-trigger read value (field 3 = paddle mask) plus its 0xFF edge
  /// notification — mirroring how the real derailleur reports a press.
  void pressPaddle(int serial) {
    final event = Uint8List(15);
    event[0] = 1;
    event[1] = 2;
    event[10] = serial & 0xff;
    event[11] = (serial >> 8) & 0xff;
    event[12] = (serial >> 16) & 0xff;
    event[13] = (serial >> 24) & 0xff;
    event[14] = 3;
    env.ble.notify(peripheral.deviceId, prop.SramAxs.componentEventChar, event);

    peripheral.readValues[_lc(prop.SramAxs.controlTriggerChar)] =
        SramEax.encrypt(sessionKey, Uint8List.fromList([0x18, 0x01]), SramEax.randomNonce());
    env.ble.notify(peripheral.deviceId, prop.SramAxs.controlTriggerChar, [0xFF]);
  }
}

/// End-to-end SRAM AXS shifter chain: fake-BLE `srambond` handshake -> guided
/// setup (bond + backup + disable on-device shifting) -> encrypted button
/// press -> decoded logical button -> keymap/action dispatch. Everything real
/// except the BLE platform and the final action executor (StubActions records
/// instead of pressing keys).
Future<void> main() async {
  final env = await IntegrationEnv.setUp();
  late StubActions stubActions;

  core.connection.initialize();

  setUp(() async {
    await env.resetState();
    stubActions = StubActions();
    stubActions.supportedApp = Zwift();
    core.actionHandler = stubActions;
  });

  tearDown(() async {
    await env.resetConnection();
  });

  Future<(FakeSramDerailleur, SramAxs)> connectSram() async {
    final derailleur = FakeSramDerailleur(env);
    env.ble.addPeripheral(derailleur.peripheral);
    await core.connection.performScanning();
    await IntegrationEnv.waitFor(
      () => core.connection.devices.whereType<SramAxs>().isNotEmpty,
      description: 'SRAM AXS derailleur in device list',
    );
    final device = core.connection.devices.whereType<SramAxs>().first;
    // handleServices() (which wires up SramAxsLogic/SramBleTransport and
    // subscribes to the control-trigger/component-event/bond characteristics)
    // runs as the tail of BluetoothDevice.connect() — the device is already
    // in core.connection.devices before that finishes. Wait for the
    // subscribe side effect so setupControl() doesn't race a still-null
    // internal logic instance (mirrors waiting on the Zwift RideOn write in
    // controller_button_chain_test.dart).
    await IntegrationEnv.waitFor(
      () => derailleur.peripheral.subscriptions.isNotEmpty,
      description: 'SRAM AXS handleServices subscriptions',
    );
    return (derailleur, device);
  }

  test('bonds, disables on-device shifting, and decodes a paddle press', () async {
    final (derailleur, device) = await connectSram();

    await device.setupControl();

    expect(device.isBonded, isTrue, reason: 'srambond handshake should have produced a session key');
    expect(device.isShiftingDisabled, isTrue);
    expect(derailleur.derailleurUnassigned, isTrue, reason: 'disableShifting() should have cleared a reaction slot');

    derailleur.pressPaddle(0x12345678);

    await IntegrationEnv.waitFor(
      () => stubActions.performedActions.isNotEmpty,
      description: 'performed action for the decoded paddle press',
    );

    expect(device.availableButtons.any((b) => b.name.contains('Shifter A')), isTrue);
    final action = stubActions.performedActions.single;
    expect(action.button.name, contains('Shifter A'));
    expect(action.trigger, ButtonTrigger.singleClick);
  });

  // NOTE on trigger semantics: SramAxs resolves its own tap-count gesture
  // (single vs double tap) into TWO DIFFERENT logical buttons — e.g. "...
  // Paddle" (default action shiftUp) vs "... Paddle (double)" (default action
  // shiftDown) — before ever calling into BaseDevice.handleButtonsClicked.
  // That base-class machinery always fires ButtonTrigger.singleClick for a
  // plain click/release pair (SramAxs sets supportsLongPress: false, so no
  // long-press or generic double-click detection ever engages there). So the
  // observable signal for "a double tap happened" is which BUTTON fired
  // (name contains "(double)"), not PerformedAction.trigger.
  test('same-identity double tap resolves to one double-tap action, not two singles', () async {
    final (derailleur, device) = await connectSram();
    await device.setupControl();

    // Two taps on the SAME controller serial, back to back, well inside the
    // (default 350ms) double-click window.
    derailleur.pressPaddle(0x11111111);
    derailleur.pressPaddle(0x11111111);

    await IntegrationEnv.waitFor(
      () => stubActions.performedActions.isNotEmpty,
      description: 'double-tap action',
    );
    // Wait past the window to be sure no extra single fires afterwards.
    await Future<void>.delayed(const Duration(milliseconds: 450));

    expect(stubActions.performedActions.length, 1);
    expect(stubActions.performedActions.single.button.name, contains('(double)'));
    expect(stubActions.performedActions.single.trigger, ButtonTrigger.singleClick);
  });

  test('a press from a different identity flushes the pending single instead of merging into a double', () async {
    final (derailleur, device) = await connectSram();
    await device.setupControl();

    // serialA's press starts a pending single-click window; serialB's press
    // (different identity, same paddle mask) arrives before that window
    // elapses. It must NOT be merged into a double attributed to serialB —
    // serialA's press flushes immediately as its own single, and serialB
    // starts its own fresh window.
    derailleur.pressPaddle(0x11111111);
    derailleur.pressPaddle(0x22222222);

    await IntegrationEnv.waitFor(
      () => stubActions.performedActions.length >= 2,
      timeout: const Duration(seconds: 2),
      description: 'two independent single-click actions',
    );

    expect(stubActions.performedActions.length, 2);
    expect(stubActions.performedActions.every((a) => !a.button.name.contains('(double)')), isTrue);
    expect(stubActions.performedActions.every((a) => a.trigger == ButtonTrigger.singleClick), isTrue);
    // Different serials => different "Shifter" labels, assigned in first-seen order.
    expect(stubActions.performedActions[0].button.name, contains('Shifter A'));
    expect(stubActions.performedActions[1].button.name, contains('Shifter B'));
  });
}
