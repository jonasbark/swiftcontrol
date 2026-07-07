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

  /// Logged once per connection when a press can't be decoded, so it's clear
  /// from the logs whether the session key is active this session.
  bool _loggedDegradedPress = false;

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

  /// Look up a pressing shifter's advertised type/model by serial (from scan adverts).
  SramDeviceInfo? _shifterInfo(int? serial) {
    if (serial == null) return null;
    for (final info in core.connection.sramShifterAdverts) {
      if (info.serial == serial) return info;
    }
    return null;
  }

  /// Pure naming from an (optional) advert + serial + mask. Exposed for tests.
  String buttonNameFor(SramDeviceInfo? info, int? serial, int? mask) {
    if (serial == null && mask == null) return 'SRAM Button';
    final side = _sideLabel(info, serial); // 'Left'/'Right' (type 0/1), else 'Shifter A/B', else ''
    if (mask == null) return side.isEmpty ? 'SRAM Button' : 'SRAM $side';
    final role = SramShifterButtons.nameFor(info?.deviceType, info?.model, mask);
    // Drop-bar mask-1 names already encode the side ("Left Shifter"/"Right Shifter").
    if (role.startsWith('Left ') || role.startsWith('Right ')) return 'SRAM $role';
    return side.isEmpty ? 'SRAM $role' : 'SRAM $side – $role';
  }

  /// Stable name for one physical (shifter, button). Single vs double click is
  /// handled by the base device from the keymap, not encoded in the name.
  String logicalButtonName(int? serial, int? mask) => buttonNameFor(_shifterInfo(serial), serial, mask);

  String _sideLabel(SramDeviceInfo? info, int? serial) {
    if (info?.deviceType == 0) return 'Left';
    if (info?.deviceType == 1) return 'Right';
    if (serial != null) return 'Shifter ${_shifterLabel(serial)}';
    return '';
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

    // Pre-register buttons for nearby SRAM shifters (§6.4) so they show up in the
    // keymap without needing a press.
    for (final info in core.connection.sramShifterAdverts) {
      for (final mask in SramShifterButtons.masksFor(info.deviceType, info.model)) {
        final name = buttonNameFor(info, info.serial, mask);
        getOrAddButton(name, () => ControllerButton(name, action: InGameAction.shiftUp, sourceDeviceId: device.deviceId));
      }
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
      if (mask == null && !_loggedDegradedPress) {
        _loggedDegradedPress = true;
        actionStreamInternal.add(
          LogNotification(
            'SramAxs: press received but not decoded — the bond session key is not active this '
            'session (using plaintext). Full per-button decoding and setup/restore need '
            're-authorizing (Set up SRAM control → press and hold the AXS button).',
          ),
        );
      }
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
      // Ensure a working bond (re-bonds if a persisted key went stale).
      await logic.ensureBonded();
      await core.settings.setSramKey(_serialKey, _bytesToHex(logic.sessionKey!));
      // Capture the ORIGINAL config exactly once. Never overwrite a saved backup:
      // a re-run (or a mid-unassign failure retry) reads the already-cleared
      // device and would otherwise wipe the only copy of the user's config.
      if (core.settings.getSramBackup(_serialKey) == null) {
        final backup = await logic.backupConfig();
        await core.settings.setSramBackup(_serialKey, backup);
      }
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
      await core.settings.setSramKey(_serialKey, _bytesToHex(logic.sessionKey!)); // persist any re-bond
      await core.settings.setSramShiftingDisabled(_serialKey, false);
      await core.settings.clearSramBackup(_serialKey); // next setup captures fresh
      core.connection.signalChange(this);
    } catch (e, st) {
      actionStreamInternal.add(LogNotification('SramAxs restore failed: $e\n$st'));
      rethrow;
    }
  }

  bool get isBonded => _logic?.isBonded ?? false;
  bool get isShiftingDisabled => core.settings.getSramShiftingDisabled(_serialKey);

  @override
  List<Widget> showAdditionalInformation(BuildContext context) => [_buildSetupPanel(context)];

  // The setup panel lives on the main device card (showAdditionalInformation),
  // so there's no separate preferences view.
  @override
  Widget? buildPreferences(BuildContext context) => null;

  Widget _buildSetupPanel(BuildContext context) {
    final hasBackup = core.settings.getSramBackup(_serialKey) != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          isShiftingDisabled
              ? 'On-device shifting is disabled — BikeControl controls your gears. '
                  'Each shifter button is a controller input you can map in the app.'
              : 'Let BikeControl control your shifting: it backs up your current shifter '
                  'configuration, then disables the derailleur\'s own shifting so it only '
                  'sends button presses. You can restore it anytime.',
        ).xSmall,
        const Gap(8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            // Once shifting is disabled, re-running setup is a no-op (the backup
            // is already saved and the device is already unassigned), so the only
            // meaningful action left is Restore.
            if (!isShiftingDisabled)
              PrimaryButton(
                size: ButtonSize.small,
                onPressed: () => unawaited(_runGuidedOperation(
                  context,
                  title: 'Set up SRAM control',
                  intro: 'Press and hold the AXS button on your derailleur until its light flashes '
                      'to authorize BikeControl, then tap Continue.\n\n'
                      'BikeControl will back up your current shifter configuration and disable the '
                      "derailleur's own shifting so it only sends button presses. You can restore it "
                      'anytime.',
                  successMessage: 'BikeControl now controls your gears. Each shifter button is a '
                      'controller input you can map in the app.',
                  operation: setupControl,
                )),
                child: const Text('Set up SRAM control'),
              ),
            if (hasBackup)
              SecondaryButton(
                size: ButtonSize.small,
                onPressed: () => unawaited(_runGuidedOperation(
                  context,
                  title: 'Restore original shifting',
                  intro: "This puts your derailleur's original shifting back.\n\n"
                      'If the derailleur has disconnected since setup, press and hold its AXS button '
                      'until the light flashes to re-authorize BikeControl first, then tap Continue.',
                  successMessage: 'Your original shifter configuration has been restored.',
                  operation: restoreShifting,
                )),
                child: const Text('Restore original shifting'),
              ),
          ],
        ),
      ],
    );
  }

  /// Interactive, staged runner for setup/restore: guide the AXS authorize
  /// gesture, show progress, and surface any error (notably the bond-
  /// authorization failure — which happens when the session key didn't survive
  /// a reconnect and a fresh bond is needed) with a Retry.
  Future<void> _runGuidedOperation(
    BuildContext context, {
    required String title,
    required String intro,
    required String successMessage,
    required Future<void> Function() operation,
  }) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        var stage = _SramSetupStage.instructions;
        String? errorMessage;
        return StatefulBuilder(
          builder: (context, setState) {
            Future<void> attempt() async {
              setState(() {
                stage = _SramSetupStage.running;
                errorMessage = null;
              });
              try {
                await operation();
                if (dialogContext.mounted) setState(() => stage = _SramSetupStage.success);
              } on SramBondException catch (e) {
                if (dialogContext.mounted) {
                  setState(() {
                    errorMessage = e.message;
                    stage = _SramSetupStage.error;
                  });
                }
              } catch (e) {
                if (dialogContext.mounted) {
                  setState(() {
                    errorMessage = 'Something went wrong: $e';
                    stage = _SramSetupStage.error;
                  });
                }
              }
            }

            final (String dialogTitle, String body, List<Widget> actions) = switch (stage) {
              _SramSetupStage.instructions => (
                title,
                intro,
                [
                  Button.secondary(
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    child: const Text('Cancel'),
                  ),
                  PrimaryButton(onPressed: attempt, child: const Text('Continue')),
                ],
              ),
              _SramSetupStage.running => (
                title,
                'Talking to your derailleur — keep it close and awake.',
                <Widget>[],
              ),
              _SramSetupStage.success => (
                'Done',
                successMessage,
                [
                  PrimaryButton(
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    child: const Text('Done'),
                  ),
                ],
              ),
              _SramSetupStage.error => (
                "That didn't work",
                errorMessage ?? 'Something went wrong. Please try again.',
                [
                  Button.secondary(
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    child: const Text('Cancel'),
                  ),
                  PrimaryButton(onPressed: attempt, child: const Text('Retry')),
                ],
              ),
            };

            return Container(
              constraints: const BoxConstraints(maxWidth: 480),
              child: AlertDialog(
                title: Text(dialogTitle),
                content: Text(body),
                actions: actions,
              ),
            );
          },
        );
      },
    );
    core.connection.signalChange(this);
  }
}

enum _SramSetupStage { instructions, running, success, error }

class SramAxsConstants {
  static const String SERVICE_UUID = "0000fe51-0000-1000-8000-00805f9b34fb";
  static const String SERVICE_UUID_RELEVANT = "d9050053-90aa-4c7c-b036-1e01fb8eb7ee";

  static const String TRIGGER_UUID = "d9050054-90aa-4c7c-b036-1e01fb8eb7ee";
}
