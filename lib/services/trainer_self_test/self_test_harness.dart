import 'package:bike_control/bluetooth/devices/proxy/proxy_device.dart';
import 'package:flutter/foundation.dart';
import 'package:prop/emulators/definitions/fitness_bike_definition.dart';
import 'package:prop/utils/shared.dart' show Logger;

abstract class SelfTestHarness {
  ValueListenable<int?> get powerW;
  ValueListenable<int?> get cadenceRpm;
  bool get upstreamConnected;
  bool get trainerAppConnected;
  bool get supportsPowerTarget;
  String get vsModeName; // VirtualShiftingMode.name
  String get protocolName; // TrainerControlProtocol.name
  bool get isErgMode; // trainerMode == TrainerMode.ergMode
  int? get ergTarget;
  int get currentGear;
  int get maxGear;
  ControlWriteResult? get lastControlWrite;
  void setErgTarget(int watts);
  void exitErg();
  void shiftUp();
  void shiftDown();
  void log(String message);
}

class FitnessBikeHarness implements SelfTestHarness {
  FitnessBikeHarness(this.device) : _def = device.fitnessBike!;
  final ProxyDevice device;
  final FitnessBikeDefinition _def;

  @override
  ValueListenable<int?> get powerW => _def.powerW;
  @override
  ValueListenable<int?> get cadenceRpm => _def.cadenceRpm;
  @override
  bool get upstreamConnected => device.isConnected;
  @override
  bool get trainerAppConnected => device.isConnectedListenable.value;
  @override
  bool get supportsPowerTarget => _def.supportsVirtualShiftingMode(VirtualShiftingMode.targetPower);
  @override
  String get vsModeName => _def.virtualShiftingMode.value.name;
  @override
  String get protocolName => _def.controlProtocol.name;
  @override
  bool get isErgMode => _def.trainerMode.value == TrainerMode.ergMode;
  @override
  int? get ergTarget => _def.ergTargetPower.value;
  @override
  int get currentGear => _def.currentGear.value;
  @override
  int get maxGear => _def.maxGear;
  @override
  ControlWriteResult? get lastControlWrite => _def.lastControlWrite;
  @override
  void setErgTarget(int watts) => _def.setManualErgPower(watts);
  @override
  void exitErg() => _def.exitErgMode();
  @override
  void shiftUp() => _def.shiftUp();
  @override
  void shiftDown() => _def.shiftDown();
  @override
  void log(String message) => Logger.info('Self-test: $message');
}
