import 'package:bike_control/bluetooth/devices/bluetooth_device.dart';
import 'package:bike_control/bluetooth/incline/incline_manual_state.dart';
import 'package:bike_control/bluetooth/incline/incline_sink.dart';
import 'package:bike_control/main.dart';
import 'package:bike_control/utils/actions/base_actions.dart';
import 'package:bike_control/utils/keymap/buttons.dart';
import 'package:bike_control/utils/keymap/keymap.dart';
import 'package:dartx/dartx.dart';

/// Shared manual-incline behavior for incline devices (KICKR Climb, Elite Rizer).
/// Holds the auto/manual state and maps the incline in-game actions to it, then
/// writes via the device-specific [writeInclineRaw]. `auto` follows the bridge
/// grade (the InclineController pushes it); `manual` holds a user-set incline.
mixin ManualInclineDevice on BluetoothDevice implements InclineSink {
  final InclineManualState inclineState = InclineManualState();

  @override
  bool get followsGrade => inclineState.mode == InclineMode.auto;

  /// Device-specific BLE write of the incline (0.01% signed). Returns true if issued.
  @override
  Future<bool> writeInclineRaw(int grade001Pct);

  Future<ActionResult> handleKeypair(KeyPair keyPair, {required bool isKeyDown}) async {
    if (!isKeyDown) return NotHandled('', button: keyPair.buttons.firstOrNull);
    try {
      switch (keyPair.inGameAction) {
        case InGameAction.inclineIncrease:
          inclineState.increase();
        case InGameAction.inclineDecrease:
          inclineState.decrease();
        case InGameAction.inclineZero:
          inclineState.zero();
        case InGameAction.inclineAutoMode:
          inclineState.setAuto();
          return Success('Incline: follow grade', button: keyPair.buttons.firstOrNull);
        default:
          return NotHandled('', button: keyPair.buttons.firstOrNull);
      }
      await writeInclineRaw(inclineState.grade001);
      return Success(
        'Incline ${(inclineState.grade001 / 100).toStringAsFixed(1)}%',
        button: keyPair.buttons.firstOrNull,
      );
    } catch (e, s) {
      recordError(e, s, context: 'ManualInclineDevice: handleKeypair failed');
      return Error('Failed to control incline: $e', button: keyPair.buttons.firstOrNull);
    }
  }
}
