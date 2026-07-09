import 'package:bike_control/bluetooth/devices/sram/sram_axs.dart';
import 'package:bike_control/utils/actions/base_actions.dart';
import 'package:bike_control/utils/core.dart';
import 'package:bike_control/utils/keymap/buttons.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:universal_ble/universal_ble.dart';

/// Records the click/combo emits the gesture engine makes, bypassing the base
/// device's own single/double-click timing so we can assert exactly what SramAxs
/// hands it. A SRAM press is one discrete 0xFF edge, so each click is emitted as
/// a down (`[buttons]`) immediately followed by an up (`[]`).
class _RecordingSramAxs extends SramAxs {
  _RecordingSramAxs() : super(BleDevice(deviceId: 'dev1', name: 'SRAM 42'));
  final List<List<String>> emitted = [];

  @override
  Future<void> handleButtonsClicked(List<ControllerButton>? buttons, {bool longPress = false}) async {
    emitted.add(buttons == null ? ['<null>'] : buttons.map((b) => b.name).toList());
  }
}

ControllerButton _btn(String name) => ControllerButton(name, action: InGameAction.shiftUp, sourceDeviceId: 'dev1');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  core.actionHandler = StubActions();

  test('a single press emits one discrete click (down then up)', () {
    fakeAsync((async) {
      final d = _RecordingSramAxs();
      d.onPress(_btn('SRAM Left Shifter'));
      async.elapse(const Duration(milliseconds: 120)); // combo window closes
      expect(d.emitted, [
        ['SRAM Left Shifter'],
        <String>[],
      ]);
    });
  });

  test('both levers within the combo window are emitted together in ONE click', () {
    fakeAsync((async) {
      final d = _RecordingSramAxs();
      d.onPress(_btn('SRAM Left Shifter'));
      async.elapse(const Duration(milliseconds: 30)); // the other lever, slightly skewed
      d.onPress(_btn('SRAM Right Shifter'));
      async.elapse(const Duration(milliseconds: 120)); // combo window closes
      // ONE down carrying BOTH buttons → base device runs the front-shift combo.
      expect(d.emitted.first.toSet(), {'SRAM Left Shifter', 'SRAM Right Shifter'});
      expect(d.emitted.last, isEmpty); // then release
      expect(d.emitted.length, 2);
    });
  });

  test('a held lever (one edge, no burst) is just a single click', () {
    fakeAsync((async) {
      final d = _RecordingSramAxs();
      d.onPress(_btn('SRAM Left Shifter')); // hold = a single 0xFF, nothing more
      async.elapse(const Duration(milliseconds: 2000));
      expect(d.emitted, [
        ['SRAM Left Shifter'],
        <String>[],
      ]);
    });
  });

  test('two separate taps are two separate clicks (base device decides single vs double)', () {
    fakeAsync((async) {
      final d = _RecordingSramAxs();
      final left = _btn('SRAM Left Shifter');
      d.onPress(left);
      async.elapse(const Duration(milliseconds: 200));
      d.onPress(left);
      async.elapse(const Duration(milliseconds: 200));
      expect(d.emitted, [
        ['SRAM Left Shifter'],
        <String>[],
        ['SRAM Left Shifter'],
        <String>[],
      ]);
    });
  });
}
