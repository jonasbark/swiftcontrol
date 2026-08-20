import 'package:bike_control/services/trainer_self_test/self_test_harness.dart';
import 'package:flutter/foundation.dart';
import 'package:prop/emulators/definitions/fitness_bike_definition.dart' show ControlWriteResult;

/// In-memory [SelfTestHarness] for engine tests: no BLE, no timers.
///
/// The test's fake sleeper calls [publishTick] once per engine tick, so one
/// `sleep` call == one sample update.
class FakeSelfTestHarness implements SelfTestHarness {
  final powerN = ValueNotifier<int?>(null);
  final cadenceN = ValueNotifier<int?>(null);

  @override
  ValueListenable<int?> get powerW => powerN;
  @override
  ValueListenable<int?> get cadenceRpm => cadenceN;
  @override
  bool upstreamConnected = true;
  @override
  bool trainerAppConnected = false;
  @override
  bool supportsPowerTarget = true;
  @override
  String vsModeName = 'targetPower';
  @override
  String protocolName = 'ftms';
  @override
  List<String> supportedProtocolNames = ['ftms'];

  bool ergMode = false;
  int? _ergTarget;
  int gear = 12;

  @override
  bool get isErgMode => ergMode;
  @override
  int? get ergTarget => _ergTarget;
  @override
  int get currentGear => gear;
  @override
  int maxGear = 24;
  @override
  ControlWriteResult? lastControlWrite;

  final logLines = <String>[];

  /// Behavior knobs per scenario:
  /// obeysErg: power converges to erg target next tick.
  /// obeysShift: power rises ~10 W per gear.
  bool obeysErg = true;
  bool obeysShift = true;
  int riderPower = 150;
  int riderCadence = 85;

  @override
  void setErgTarget(int watts) {
    ergMode = true;
    _ergTarget = watts;
  }

  @override
  void exitErg() {
    ergMode = false;
    _ergTarget = null;
  }

  @override
  void setVsMode(String modeName) => vsModeName = modeName;

  @override
  void setProtocol(String name) => protocolName = name;

  @override
  void shiftUp() => gear++;
  @override
  void shiftDown() => gear--;
  @override
  void log(String m) => logLines.add(m);

  /// Called by the test's fake sleeper each tick to publish samples.
  void publishTick() {
    cadenceN.value = riderCadence;
    if (ergMode && obeysErg) {
      powerN.value = _ergTarget;
      return;
    }
    powerN.value = obeysShift ? riderPower + (gear - 12) * 10 : riderPower;
  }
}
