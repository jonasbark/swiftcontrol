import 'dart:async';
import 'dart:typed_data';

import 'package:bike_control/bluetooth/devices/sram/sram_axs.dart';
import 'package:bike_control/utils/actions/base_actions.dart';
import 'package:bike_control/utils/core.dart';
import 'package:bike_control/utils/keymap/buttons.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
// prop.dart exports a `SramAxs` constants class that collides with the app's
// `SramAxs` device class — bring it in under a prefix.
import 'package:prop/prop.dart' as prop;
import 'package:shared_preferences/shared_preferences.dart';
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

  // The §7 burst guard reads isShiftingDisabled from settings.
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    core.settings.prefs = await SharedPreferences.getInstance();
  });

  /// Feed one raw 0xFF trigger edge through processCharacteristic — the
  /// production entry point, INCLUDING the §7 burst guard (unlike onPress,
  /// which enters the gesture engine below it).
  void edge(_RecordingSramAxs d) => unawaited(
        d.processCharacteristic(prop.SramAxs.controlTriggerChar, Uint8List.fromList(const [0xFF])),
      );

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

  test('a same-lever repeat inside the combo window is a duplicate (iOS read echo) and coalesces', () {
    fakeAsync((async) {
      final d = _RecordingSramAxs();
      final left = _btn('SRAM Left Shifter');
      d.onPress(left);
      async.elapse(const Duration(milliseconds: 30)); // the echoed read response lands in the window
      d.onPress(left);
      async.elapse(const Duration(milliseconds: 120)); // combo window closes
      // A finger can't re-press the same lever within 90ms — a same-name press
      // inside the window is the §6.1 iOS read-response echo of the same tap,
      // so it must coalesce into ONE click, never actuate twice.
      expect(d.emitted, [
        ['SRAM Left Shifter'],
        <String>[],
      ]);
    });
  });

  test('an echoed left inside the window does not break the left+right combo', () {
    fakeAsync((async) {
      final d = _RecordingSramAxs();
      d.onPress(_btn('SRAM Left Shifter'));
      async.elapse(const Duration(milliseconds: 30));
      d.onPress(_btn('SRAM Left Shifter')); // echo of the same tap → coalesced
      async.elapse(const Duration(milliseconds: 30));
      d.onPress(_btn('SRAM Right Shifter')); // the other lever, still inside the window
      async.elapse(const Duration(milliseconds: 120));
      // ONE combined emit → the base device runs the front-shift combo.
      expect(d.emitted.length, 2);
      expect(d.emitted[0].toSet(), {'SRAM Left Shifter', 'SRAM Right Shifter'});
      expect(d.emitted[1], isEmpty);
    });
  });

  test('§7 guard (shifting enabled): a burst chain forwards two edges, drops the rest, re-arms after silence', () {
    fakeAsync((async) {
      final d = _RecordingSramAxs();
      // Fresh device, no setup → shifting is NOT disabled → the derailleur can
      // multishift while held, so the burst guard is active.
      edge(d); // t=0    → forwarded (1st of chain)
      async.elapse(const Duration(milliseconds: 150));
      edge(d); // t=150  → forwarded (2nd of chain — keeps double-click alive)
      async.elapse(const Duration(milliseconds: 150));
      edge(d); // t=300  → 3rd rapid trigger → dropped
      async.elapse(const Duration(milliseconds: 150));
      edge(d); // t=450  → still inside the sliding chain → dropped
      // Forwarded edges are >90ms apart, so each is its own click: 2 clicks.
      async.elapse(const Duration(milliseconds: 200));
      expect(d.emitted.length, 4);
      // ≥350ms of silence resets the chain → the next edge is a fresh press.
      async.elapse(const Duration(milliseconds: 400));
      edge(d);
      async.elapse(const Duration(milliseconds: 200));
      expect(d.emitted.length, 6);
    });
  });

  test('no §7 guard once shifting is disabled: every spaced tap is delivered', () {
    fakeAsync((async) {
      final d = _RecordingSramAxs();
      // Post-setup state: shifting disabled → a held lever emits exactly ONE
      // edge (verified by --observe, see 16fad263), so every edge is a genuine
      // tap and none may be swallowed — even at a fast ~150ms cadence.
      core.settings.setSramShiftingDisabled('dev1', true);
      async.flushMicrotasks();
      for (var i = 0; i < 4; i++) {
        edge(d);
        async.elapse(const Duration(milliseconds: 150));
      }
      async.elapse(const Duration(milliseconds: 200));
      expect(d.emitted.length, 8); // 4 clicks × (down + up)
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
