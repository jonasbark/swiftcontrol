import 'package:bike_control/bluetooth/devices/proxy/proxy_device.dart';
import 'package:bike_control/utils/core.dart';
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

  /// Every control-protocol delivery this trainer's advertised services can
  /// actually carry, by [TrainerControlProtocol.name] — see
  /// [FitnessBikeDefinition.supportedControlProtocols].
  List<String> get supportedProtocolNames;
  bool get isErgMode; // trainerMode == TrainerMode.ergMode
  int? get ergTarget;
  int get currentGear;
  int get maxGear;
  ControlWriteResult? get lastControlWrite;
  void setErgTarget(int watts);
  void exitErg();

  /// Sets the virtual-shifting mode by [VirtualShiftingMode.name] — a string
  /// rather than the enum itself so the fake-backed tests don't need the prop
  /// package's definition to observe it.
  void setVsMode(String modeName);

  /// Forces the control-protocol delivery by [TrainerControlProtocol.name] —
  /// same fake-friendly string reasoning as [setVsMode] — and persists it as
  /// the rider's override for this trainer.
  void setProtocol(String name);
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
  List<String> get supportedProtocolNames => _def.supportedControlProtocols.map((p) => p.name).toList();
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
  void setVsMode(String modeName) => _def.setVirtualShiftingMode(VirtualShiftingMode.values.byName(modeName));
  @override
  void setProtocol(String name) {
    _def.setControlProtocolOverride(TrainerControlProtocol.values.byName(name));
    core.settings.setControlProtocolOverride(device.trainerKey, name);
  }

  @override
  void shiftUp() => _def.shiftUp();
  @override
  void shiftDown() => _def.shiftDown();
  @override
  void log(String message) => Logger.info('Self-test: $message');
}
