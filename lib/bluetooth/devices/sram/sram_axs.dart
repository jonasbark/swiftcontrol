import 'dart:async';

import 'package:bike_control/bluetooth/messages/notification.dart';
import 'package:bike_control/utils/core.dart';
import 'package:bike_control/utils/keymap/buttons.dart';
import 'package:dartx/dartx.dart';
import 'package:flutter/foundation.dart';
// The prop package exports a `SramAxs` constants class with the same name as
// this file's `SramAxs` device class. Hide it from the wildcard import and
// pull it back in under a prefix so both symbols stay unambiguous.
import 'package:prop/prop.dart' hide SramAxs;
import 'package:prop/prop.dart' as sram_proto show SramAxs;
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:universal_ble/universal_ble.dart';

import '../bluetooth_device.dart';
import 'sram_ble_transport.dart';

class SramAxs extends BluetoothDevice {
  SramAxs(super.scanResult) : super(availableButtons: [], isBeta: true, supportsLongPress: false);

  SramBleTransport? _transport;
  SramAxsLogic? _logic;

  Timer? _singleClickTimer;
  int _tapCount = 0;
  int? _pendingSerial;
  int? _pendingMask;

  /// Stable "Shifter A/B/..." labels assigned to controller serials in the
  /// order they are first seen.
  final List<int> _serialOrder = [];

  String get _serialKey => device.deviceId;

  String _shifterLabel(int? serial) {
    if (serial == null) return '';
    var idx = _serialOrder.indexOf(serial);
    if (idx == -1) {
      _serialOrder.add(serial);
      idx = _serialOrder.length - 1;
    }
    return String.fromCharCode('A'.codeUnitAt(0) + idx);
  }

  /// Pure naming used for both discovery and the gesture emit. Exposed for tests.
  String logicalButtonName(int? serial, int? mask, {required bool doubleTap}) {
    if (serial == null && mask == null) {
      return doubleTap ? 'SRAM Double Tap' : 'SRAM Tap';
    }
    final button = mask == null
        ? null
        : (mask == sram_proto.SramAxs.paddleMask ? 'Paddle' : 'Button 0x${mask.toRadixString(16)}');
    if (serial == null) {
      // Button known, shifter not yet identified (press decoded before componentEvent).
      return doubleTap ? 'SRAM $button (double)' : 'SRAM $button';
    }
    final shifter = 'SRAM Shifter ${_shifterLabel(serial)}';
    if (mask == null) {
      return doubleTap ? '$shifter – Double Tap' : '$shifter – Tap';
    }
    return doubleTap ? '$shifter – $button (double)' : '$shifter – $button';
  }

  // -1 is the persisted sentinel for "null" (see Settings.addSramButton).
  static int? _fromStored(int v) => v == -1 ? null : v;

  /// Names a persisted (stored) button, mapping the `-1` sentinel back to null
  /// so re-registration never yields `"Button 0x-1"` or a phantom shifter slot.
  /// Exposed for tests.
  String storedButtonName(int storedSerial, int storedMask, {required bool doubleTap}) =>
      logicalButtonName(_fromStored(storedSerial), _fromStored(storedMask), doubleTap: doubleTap);

  @override
  Future<void> disconnect() async {
    _singleClickTimer?.cancel();
    _singleClickTimer = null;
    _tapCount = 0;
    await super.disconnect();
  }

  @override
  Future<void> handleServices(List<BleService> services) async {
    final transport = SramBleTransport(device.deviceId, services);
    final logic = SramAxsLogic(transport);
    _transport = transport;
    _logic = logic;

    // Seed a previously-persisted session key so we start bonded when possible.
    final storedKey = core.settings.getSramKey(_serialKey);
    if (storedKey != null) {
      logic.seedKey(_hexToBytes(storedKey));
    }

    // Subscribe: press trigger, component event (plaintext), bond channel.
    for (final char in [sram_proto.SramAxs.controlTriggerChar, sram_proto.SramAxs.componentEventChar, sram_proto.SramAxs.bondChar]) {
      final service = services.firstOrNullWhere((s) => s.characteristics.any((c) => c.uuid == char.toLowerCase()));
      if (service != null) {
        await UniversalBle.subscribeNotifications(device.deviceId, service.uuid, char.toLowerCase());
      } else if (char == sram_proto.SramAxs.controlTriggerChar) {
        // The trigger char is essential; without it the device can't report
        // presses. Log it so a non-functional connect is diagnosable from logs.
        actionStreamInternal.add(LogNotification('SramAxs: control-trigger characteristic $char not found'));
      }
    }

    // Re-register any previously-discovered buttons so they persist in the keymap.
    // The `-1` sentinel is mapped back to null so it never yields "Button 0x-1".
    for (final b in core.settings.getSramButtons(_serialKey)) {
      _registerButton(_fromStored(b.serial), _fromStored(b.mask));
    }
  }

  ControllerButton _registerButton(int? serial, int? mask) {
    final name = logicalButtonName(serial, mask, doubleTap: false);
    final doubleName = logicalButtonName(serial, mask, doubleTap: true);
    getOrAddButton(doubleName, () => ControllerButton(doubleName, action: InGameAction.shiftDown, sourceDeviceId: device.deviceId));
    return getOrAddButton(name, () => ControllerButton(name, action: InGameAction.shiftUp, sourceDeviceId: device.deviceId));
  }

  Future<void> _emitClick(ControllerButton button) async {
    await handleButtonsClicked([button]);
    await handleButtonsClicked([]);
  }

  bool _isPendingIdentity(int? serial, int? mask) => serial == _pendingSerial && mask == _pendingMask;

  /// Debounce a decoded press per `(serial, mask)` identity. The double-click
  /// window is scoped to a single physical button: a press from a DIFFERENT
  /// identity flushes the currently-pending single immediately, then starts a
  /// fresh window for the new identity (so two different buttons pressed close
  /// together never merge into a spurious double-click on one of them).
  void _onPress(int? serial, int? mask) {
    final windowMs = core.settings.getSramAxsDoubleClickWindowMs();

    // A press from a different physical button flushes the pending single first.
    if (_tapCount > 0 && !_isPendingIdentity(serial, mask)) {
      final s = _pendingSerial, m = _pendingMask;
      _singleClickTimer?.cancel();
      _singleClickTimer = null;
      _tapCount = 0;
      unawaited(_emitResolved(serial: s, mask: m, doubleTap: false));
    }

    _pendingSerial = serial;
    _pendingMask = mask;
    _tapCount++;

    if (_tapCount == 1) {
      _singleClickTimer?.cancel();
      _singleClickTimer = Timer(Duration(milliseconds: windowMs), () {
        final fired = _tapCount == 1;
        final s = _pendingSerial, m = _pendingMask;
        _tapCount = 0;
        _singleClickTimer = null;
        if (fired) unawaited(_emitResolved(serial: s, mask: m, doubleTap: false));
      });
      return;
    }

    // 2+ taps on the SAME identity within the window → double click.
    _singleClickTimer?.cancel();
    _singleClickTimer = null;
    final s = _pendingSerial, m = _pendingMask;
    _tapCount = 0;
    unawaited(_emitResolved(serial: s, mask: m, doubleTap: true));
  }

  Future<void> _emitResolved({required int? serial, required int? mask, required bool doubleTap}) async {
    if (serial != null || mask != null) {
      await core.settings.addSramButton(_serialKey, serial ?? -1, mask ?? -1);
    }
    final name = logicalButtonName(serial, mask, doubleTap: doubleTap);
    final button = getOrAddButton(
      name,
      () => ControllerButton(name,
          action: doubleTap ? InGameAction.shiftDown : InGameAction.shiftUp,
          sourceDeviceId: device.deviceId),
    );
    await _emitClick(button);
  }

  @override
  Future<void> processCharacteristic(String characteristic, Uint8List bytes) async {
    final lc = characteristic.toLowerCase();
    _transport?.onNotification(characteristic, bytes);

    if (lc == sram_proto.SramAxs.componentEventChar.toLowerCase()) {
      _logic?.onComponentEvent(bytes);
      return;
    }

    if (lc == sram_proto.SramAxs.controlTriggerChar.toLowerCase()) {
      // 0xFF edge → resolve identity (may read+decrypt), then run the gesture layer.
      final press = await _logic?.handleTrigger() ?? const SramPress();
      // Persist a re-bond if the key was just dropped.
      if (_logic != null && !_logic!.isBonded && core.settings.getSramKey(_serialKey) != null) {
        await core.settings.setSramKey(_serialKey, null);
      }
      _onPress(press.controllerSerial, press.buttonMask);
    }
  }

  Uint8List _hexToBytes(String hex) => Uint8List.fromList([
        for (var i = 0; i < hex.length; i += 2) int.parse(hex.substring(i, i + 2), radix: 16),
      ]);

  String _bytesToHex(Uint8List b) => b.map((e) => e.toRadixString(16).padLeft(2, '0')).join();

  // ── Guided setup / restore (called from the UI in Task 12) ────────────────

  Future<void> setupControl() async {
    final logic = _logic;
    if (logic == null) return;
    try {
      if (!logic.isBonded) {
        final key = await logic.bond();
        await core.settings.setSramKey(_serialKey, _bytesToHex(key));
      }
      final backup = await logic.backupConfig();
      await core.settings.setSramBackup(_serialKey, backup);
      await logic.disableShifting();
      await core.settings.setSramShiftingDisabled(_serialKey, true);
      core.connection.signalChange(this);
    } catch (e, st) {
      actionStreamInternal.add(LogNotification('SramAxs setup failed: $e\n$st'));
      rethrow;
    }
  }

  Future<void> restoreShifting() async {
    final logic = _logic;
    final backup = core.settings.getSramBackup(_serialKey);
    if (logic == null || backup == null) return;
    try {
      await logic.restoreConfig(backup);
      await core.settings.setSramShiftingDisabled(_serialKey, false);
      core.connection.signalChange(this);
    } catch (e, st) {
      actionStreamInternal.add(LogNotification('SramAxs restore failed: $e\n$st'));
      rethrow;
    }
  }

  bool get isBonded => _logic?.isBonded ?? false;
  bool get isShiftingDisabled => core.settings.getSramShiftingDisabled(_serialKey);

  @override
  List<Widget> showAdditionalInformation(BuildContext context) => const [];

  @override
  Widget? buildPreferences(BuildContext context) => _buildPreferences(context);
}

Widget? _buildPreferences(BuildContext context) => null;

class SramAxsConstants {
  static const String SERVICE_UUID = "0000fe51-0000-1000-8000-00805f9b34fb";
  static const String SERVICE_UUID_RELEVANT = "d9050053-90aa-4c7c-b036-1e01fb8eb7ee";

  static const String TRIGGER_UUID = "d9050054-90aa-4c7c-b036-1e01fb8eb7ee";
}
