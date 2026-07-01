import 'package:bike_control/bluetooth/incline/incline_sink.dart';
import 'package:bike_control/bluetooth/incline/incline_manual_state.dart';
import 'package:bike_control/main.dart';
import 'package:bike_control/utils/actions/base_actions.dart';
import 'package:bike_control/utils/keymap/buttons.dart';
import 'package:bike_control/utils/keymap/keymap.dart';
import 'package:dartx/dartx.dart';
import 'package:flutter/foundation.dart';
import 'package:prop/utils/wahoo_climb.dart';
import 'package:universal_ble/universal_ble.dart';

import '../bluetooth_device.dart';

/// Wahoo KICKR Climb — a beta accessory driven by the active bridge's sim grade
/// (auto) or by manual button actions (manual hold). Direct-to-Climb BLE sink.
class WahooKickrClimb extends BluetoothDevice with Accessory implements InclineSink {
  WahooKickrClimb(super.scanResult) : super(availableButtons: const [], isBeta: true);

  final InclineManualState state = InclineManualState();

  /// Test seam: overridable to capture writes without real BLE.
  @visibleForTesting
  Future<void> Function(Uint8List bytes)? debugWriteSink;

  InclineMode get mode => state.mode;

  @override
  bool get followsGrade => state.mode == InclineMode.auto;

  @override
  Future<void> handleServices(List<BleService> services) async {
    // Diagnostics: dump GATT so the first hardware tester can confirm the
    // proprietary service/char exist on the Climb's own peripheral.
    for (final s in services) {
      debugPrint('[Climb] service ${s.uuid} chars=${s.characteristics.map((c) => c.uuid).toList()}');
    }
    final service = services.firstOrNullWhere((e) => e.uuid == wahooClimbServiceUuid);
    if (service == null) {
      debugPrint('[Climb] proprietary service $wahooClimbServiceUuid not found — incompatible device');
      return;
    }
    final ch = service.characteristics.firstOrNullWhere((e) => e.uuid == wahooClimbCharacteristicUuid);
    if (ch == null) {
      debugPrint('[Climb] characteristic $wahooClimbCharacteristicUuid not found — incompatible device');
      return;
    }
    try {
      await UniversalBle.subscribeNotifications(device.deviceId, service.uuid, ch.uuid);
      await _write(Uint8List.fromList([wahooClimbRequestControlOpcode]));
    } catch (e, s) {
      recordError(e, s, context: 'WahooKickrClimb: request-control failed');
    }
  }

  @override
  Future<void> processCharacteristic(String characteristic, Uint8List bytes) async {
    debugPrint('[Climb] notify $characteristic: $bytes');
  }

  @override
  Future<bool> writeInclineRaw(int grade001Pct) async {
    try {
      await _write(wahooClimbInclineToBytes(grade001Pct));
      return true;
    } catch (e, s) {
      recordError(e, s, context: 'WahooKickrClimb: writeIncline failed');
      return false;
    }
  }

  Future<void> _write(Uint8List bytes) async {
    if (debugWriteSink != null) {
      await debugWriteSink!(bytes);
      return;
    }
    await UniversalBle.write(
      device.deviceId,
      wahooClimbServiceUuid,
      wahooClimbCharacteristicUuid,
      bytes,
      withoutResponse: true,
    );
  }

  /// Handles the manual Climb actions. Auto is restored by
  /// [InGameAction.climbAutoMode]; the InclineController resumes pushing grade.
  Future<ActionResult> handleKeypair(KeyPair keyPair, {required bool isKeyDown}) async {
    if (!isKeyDown) return NotHandled('', button: keyPair.buttons.firstOrNull);
    try {
      switch (keyPair.inGameAction) {
        case InGameAction.climbInclineIncrease:
          state.increase();
        case InGameAction.climbInclineDecrease:
          state.decrease();
        case InGameAction.climbInclineZero:
          state.zero();
        case InGameAction.climbAutoMode:
          state.setAuto();
          return Success('Climb: follow grade', button: keyPair.buttons.firstOrNull);
        default:
          return NotHandled('', button: keyPair.buttons.firstOrNull);
      }
      await writeInclineRaw(state.grade001);
      return Success(
        'Climb incline ${(state.grade001 / 100).toStringAsFixed(1)}%',
        button: keyPair.buttons.firstOrNull,
      );
    } catch (e) {
      return Error('Failed to control Climb: $e', button: keyPair.buttons.firstOrNull);
    }
  }
}
