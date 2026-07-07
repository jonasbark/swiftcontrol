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

  /// Stable name for one physical (shifter, button). Single vs double click is
  /// handled by the base device from the keymap, not encoded in the name.
  String logicalButtonName(int? serial, int? mask) {
    if (serial == null && mask == null) return 'SRAM Button';
    final button = mask == null
        ? null
        : (mask == sram_proto.SramAxs.paddleMask ? 'Paddle' : 'Button 0x${mask.toRadixString(16)}');
    if (serial == null) return 'SRAM $button'; // button known, shifter not yet identified
    final shifter = 'SRAM Shifter ${_shifterLabel(serial)}';
    return mask == null ? shifter : '$shifter – $button';
  }

  // -1 is the persisted sentinel for "null" (see Settings.addSramButton).
  static int? _fromStored(int v) => v == -1 ? null : v;

  /// Names a persisted (stored) button, mapping the `-1` sentinel back to null
  /// so re-registration never yields `"Button 0x-1"` or a phantom shifter slot.
  /// Exposed for tests.
  String storedButtonName(int storedSerial, int storedMask) =>
      logicalButtonName(_fromStored(storedSerial), _fromStored(storedMask));

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
    final name = logicalButtonName(serial, mask);
    return getOrAddButton(name, () => ControllerButton(name, action: InGameAction.shiftUp, sourceDeviceId: device.deviceId));
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
      // 0xFF edge → resolve identity (may read+decrypt), then emit a single
      // physical press. Single vs double click is handled by the base device.
      final press = await _logic?.handleTrigger() ?? const SramPress();
      // Persist a re-bond if the key was just dropped.
      if (_logic != null && !_logic!.isBonded && core.settings.getSramKey(_serialKey) != null) {
        await core.settings.setSramKey(_serialKey, null);
      }
      final serial = press.controllerSerial;
      final mask = press.buttonMask;
      if (serial != null || mask != null) {
        await core.settings.addSramButton(_serialKey, serial ?? -1, mask ?? -1);
      }
      final button = _registerButton(serial, mask);
      await handleButtonsClicked([button]);
      await handleButtonsClicked([]);
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
  Widget? buildPreferences(BuildContext context) {
    return StatefulBuilder(
      builder: (context, setState) {
        Future<void> run(Future<void> Function() op) async {
          try {
            await op();
          } catch (_) {
            // Errors are logged via LogNotification in setupControl/restoreShifting.
          }
          if (context.mounted) setState(() {});
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isShiftingDisabled
                  ? 'On-device shifting is disabled — BikeControl controls your gears. '
                      'Each shifter button is a controller input you can map below.'
                  : 'Set up automatic control: BikeControl backs up your current shifter '
                      'configuration, then disables the derailleur\'s own shifting so it '
                      'only sends button presses. You can restore it anytime.',
            ).xSmall,
            const Gap(8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                PrimaryButton(
                  size: ButtonSize.small,
                  onPressed: () => run(setupControl),
                  child: Text(isShiftingDisabled ? 'Re-run SRAM setup' : 'Set up SRAM control'),
                ),
                if (core.settings.getSramBackup(_serialKey) != null)
                  SecondaryButton(
                    size: ButtonSize.small,
                    onPressed: () => run(restoreShifting),
                    child: const Text('Restore original shifting'),
                  ),
              ],
            ),
          ],
        );
      },
    );
  }
}

class SramAxsConstants {
  static const String SERVICE_UUID = "0000fe51-0000-1000-8000-00805f9b34fb";
  static const String SERVICE_UUID_RELEVANT = "d9050053-90aa-4c7c-b036-1e01fb8eb7ee";

  static const String TRIGGER_UUID = "d9050054-90aa-4c7c-b036-1e01fb8eb7ee";
}
