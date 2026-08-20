import 'dart:math' as math;

import 'package:bike_control/main.dart' show recordError;
import 'package:bike_control/services/trainer_self_test/self_test_harness.dart';
import 'package:bike_control/services/trainer_self_test/self_test_result.dart';
import 'package:flutter/foundation.dart';

/// Coarse stage of a running self-test. The precheck (waiting for the first
/// power sample) runs inside [SelfTestPhase.baseline] — from the rider's point
/// of view it is all "start pedaling".
enum SelfTestPhase { idle, baseline, ergStaircase, shiftSweep, done }

/// Immutable snapshot of the engine, rebuilt on every transition.
@immutable
class SelfTestState {
  final SelfTestPhase phase;

  /// True while the "keep pedaling" banner should be shown; the current step's
  /// clock is stopped while this holds.
  final bool pausedForCadence;

  /// Non-null during [SelfTestPhase.ergStaircase] — the watt target currently
  /// commanded on the trainer.
  final int? currentErgTarget;

  /// Grow as steps finish; `true` == that step responded as commanded.
  final List<bool> ergStepResults;
  final List<bool> shiftStepResults;

  /// Non-null once [phase] == [SelfTestPhase.done].
  final SelfTestResult? result;

  const SelfTestState({
    this.phase = SelfTestPhase.idle,
    this.pausedForCadence = false,
    this.currentErgTarget,
    this.ergStepResults = const [],
    this.shiftStepResults = const [],
    this.result,
  });
}

/// Injectable delay so tests can drive the engine on a virtual clock.
typedef Sleeper = Future<void> Function(Duration);

/// Guided trainer resistance self-test: baseline → ERG staircase → shift sweep
/// → verdict.
///
/// Pure state machine — it owns no UI and no persistence. [run] returns the
/// [SelfTestResult]; storing it is the caller's job. Every phase transition and
/// step outcome is mirrored into [SelfTestHarness.log] as a short English line
/// (developer diagnostics for Activity/the support bundle, deliberately not
/// localized).
class SelfTestEngine {
  SelfTestEngine({required this.harness, Sleeper? sleep, DateTime Function()? now})
    : _sleep = sleep ?? _realSleep,
      _now = now ?? DateTime.now;

  final SelfTestHarness harness;
  final Sleeper _sleep;
  final DateTime Function() _now;

  // ---------------------------------------------------------------- timings
  /// Sampling period — everything below is expressed in whole ticks.
  static const Duration tick = Duration(milliseconds: 500);

  /// No power sample at all within this window → [SelfTestVerdict.noData].
  static const Duration noDataTimeout = Duration(seconds: 5);

  /// Cadence that counts as "pedaling" (start + resume threshold), rpm.
  static const int baselineCadenceMin = 40;

  /// Cadence must hold [baselineCadenceMin] this long before measuring.
  static const Duration baselineHold = Duration(seconds: 3);

  /// Power window whose median becomes `p0`.
  static const Duration baselineWindow = Duration(seconds: 3);

  /// Budget for one ERG step to land in band.
  static const Duration stepDuration = Duration(seconds: 8);

  /// ERG in-band tolerance: `max(ergBandFloorW, ergBandFraction * target)`.
  static const int ergBandFloorW = 15;
  static const double ergBandFraction = 0.12;

  /// Consecutive in-band ticks that make an ERG step pass.
  static const int ergInBandTicks = 2;

  /// ERG staircase targets: `[p0 + up, max(min, p0 - down), p0 + up]`.
  static const int ergStepUpW = 40;
  static const int ergStepDownW = 30;
  static const int ergStepMinW = 60;

  /// Steps that must pass for the ERG / shift phase to count as working.
  static const int stepsToPass = 2;

  /// Below this cadence the rider counts as coasting, rpm.
  static const int pauseCadenceBelow = 30;

  /// Coasting this long pauses the test.
  static const Duration pauseAfter = Duration(seconds: 4);

  /// Staying paused this long aborts it.
  static const Duration pauseTimeout = Duration(seconds: 20);

  /// Trailing window averaged into one plateau reading.
  static const Duration plateauWindow = Duration(seconds: 4);

  /// Upshifts scored during the sweep, and the gears kept free for them.
  static const int shiftTransitions = 3;
  static const int headroomGears = 3;

  /// A transition must not be explained by the rider spinning up/down.
  static const double cadenceDriftTolerance = 0.15;

  /// Safety stop for the gear-restore loop (a trainer may refuse to shift).
  static const int maxRestoreShifts = 60;

  // ------------------------------------------------------------------ state
  final ValueNotifier<SelfTestState> _state = ValueNotifier(const SelfTestState());

  ValueListenable<SelfTestState> get state => _state;

  Future<SelfTestResult>? _runFuture;
  bool _cancelled = false;

  SelfTestPhase _phase = SelfTestPhase.idle;
  bool _paused = false;
  int? _currentErgTarget;
  final List<bool> _ergResults = [];
  final List<bool> _shiftResults = [];
  SelfTestResult? _result;

  /// Latest samples, refreshed by [_tick].
  int? _power;
  int? _cadence;

  /// Pause bookkeeping.
  bool _pauseArmed = false;
  int _lowCadenceTicks = 0;
  int _pausedTicks = 0;

  /// Steps actually scored (0 for a skipped ERG phase).
  int _ergTotal = 0;
  int _shiftTotal = 0;

  /// Baseline power, kept for the ERG-restore fallback.
  int? _p0;

  /// Set while our own writes still need undoing.
  bool _ergDirty = false;
  bool _gearDirty = false;

  /// Runs the whole test. Safe to call repeatedly — later calls join the first.
  Future<SelfTestResult> run() => _runFuture ??= _run();

  /// Ends the test at the next tick with [SelfTestVerdict.aborted]; restore
  /// still runs.
  void cancel() {
    if (_cancelled || _phase == SelfTestPhase.done) {
      return;
    }
    _cancelled = true;
  }

  Future<SelfTestResult> _run() async {
    // 1. Snapshot everything we are about to disturb.
    final wasErg = harness.isErgMode;
    final prevErgTarget = harness.ergTarget;
    final startGear = harness.currentGear;
    SelfTestVerdict? verdict;
    try {
      harness.log('start: vs=${harness.vsModeName} protocol=${harness.protocolName} gear=$startGear erg=$wasErg');
      _phase = SelfTestPhase.baseline;
      _emit();
      if (!await _precheck()) {
        harness.log('precheck: no power for ${noDataTimeout.inSeconds}s -> NO_DATA');
        verdict = SelfTestVerdict.noData;
      } else {
        final p0 = await _baseline();
        await _ergStaircase(p0, wasErg: wasErg, prevErgTarget: prevErgTarget);
        await _shiftSweep(startGear: startGear);
      }
    } on _AbortedException catch (e) {
      harness.log('aborted: ${e.reason}');
      verdict = SelfTestVerdict.aborted;
    } catch (e, s) {
      recordError(e, s, context: 'self-test run');
      harness.log('aborted: engine error ($e)');
      verdict = SelfTestVerdict.aborted;
    }
    return _finish(verdict: verdict, wasErg: wasErg, prevErgTarget: prevErgTarget, startGear: startGear);
  }

  // ----------------------------------------------------------------- phases
  /// 2. Precheck — a trainer that never reports power cannot be tested.
  Future<bool> _precheck() async {
    for (var i = 0; i < _ticksIn(noDataTimeout); i++) {
      await _tick();
      if (_power != null) {
        harness.log('precheck: power data present (${_power}W)');
        return true;
      }
    }
    return false;
  }

  /// 3. Baseline — hold cadence, then take the median power as `p0`.
  Future<int> _baseline() async {
    // The pause watchdog only arms here: a slow first sample during the
    // precheck must not count as coasting.
    _pauseArmed = true;
    harness.log('baseline: waiting for cadence >= $baselineCadenceMin rpm');
    var held = 0;
    while (held < _ticksIn(baselineHold)) {
      if (!await _tick()) {
        continue;
      }
      held = (_cadence ?? 0) >= baselineCadenceMin ? held + 1 : 0;
    }
    var sampled = 0;
    final samples = <int>[];
    while (sampled < _ticksIn(baselineWindow)) {
      if (!await _tick()) {
        continue;
      }
      sampled++;
      final p = _power;
      if (p != null) {
        samples.add(p);
      }
    }
    final p0 = _median(samples);
    _p0 = p0;
    harness.log('baseline: p0=${p0}W from ${samples.length} samples');
    return p0;
  }

  /// 4. ERG staircase — command targets and watch whether power follows.
  Future<void> _ergStaircase(int p0, {required bool wasErg, required int? prevErgTarget}) async {
    _phase = SelfTestPhase.ergStaircase;
    _emit();
    harness.log('phase: erg staircase');
    if (!harness.supportsPowerTarget) {
      // Skipped, not failed: ergStepsTotal stays 0 and the verdict ignores it.
      harness.log('erg: skipped, trainer has no power-target support');
      return;
    }
    final targets = [p0 + ergStepUpW, math.max(ergStepMinW, p0 - ergStepDownW), p0 + ergStepUpW];
    try {
      for (final target in targets) {
        _currentErgTarget = target;
        _emit();
        harness.log('erg: commanding ${target}W');
        _ergDirty = true;
        harness.setErgTarget(target);
        final passed = await _ergStep(target);
        _ergTotal++;
        _ergResults.add(passed);
        harness.log('erg: ${target}W ${passed ? 'reached' : 'no response'}');
        _emit();
      }
    } finally {
      // Undo our own ERG writes as soon as the staircase ends (also on cancel
      // or abort mid-step): the test must never exit leaving the trainer in an
      // ERG mode we put it in.
      _currentErgTarget = null;
      _restoreErg(wasErg: wasErg, prevErgTarget: prevErgTarget);
      _emit();
    }
  }

  Future<bool> _ergStep(int target) async {
    final tolerance = math.max(ergBandFloorW.toDouble(), ergBandFraction * target);
    var elapsed = 0;
    var inBand = 0;
    while (elapsed < _ticksIn(stepDuration)) {
      if (!await _tick()) {
        continue;
      }
      elapsed++;
      final p = _power;
      if (p != null && (p - target).abs() <= tolerance) {
        inBand++;
        if (inBand >= ergInBandTicks) {
          return true;
        }
      } else {
        inBand = 0;
      }
    }
    return false;
  }

  /// 5. Shift sweep — three upshifts, each expected to harden the resistance.
  Future<void> _shiftSweep({required int startGear}) async {
    _phase = SelfTestPhase.shiftSweep;
    _emit();
    harness.log('phase: shift sweep');
    try {
      // Headroom: leave room for the upshifts before measuring anything.
      while (harness.currentGear > harness.maxGear - headroomGears) {
        if (!await _tick()) {
          continue;
        }
        harness.shiftDown();
        _gearDirty = true;
        harness.log('shift: headroom -> gear ${harness.currentGear}');
      }
      var previous = await _plateau();
      harness.log(
        'shift: gear ${harness.currentGear} plateau ${_w(previous.power)} @ ${previous.cadence.round()}rpm',
      );
      for (var i = 0; i < shiftTransitions; i++) {
        harness.shiftUp();
        _gearDirty = true;
        var current = await _plateau();
        var passed = _transitionPassed(current, previous);
        if (!passed) {
          // One retry per plateau — re-measure, do not shift again.
          harness.log('shift: gear ${harness.currentGear} inconclusive, re-measuring');
          current = await _plateau();
          passed = _transitionPassed(current, previous);
        }
        _shiftTotal++;
        _shiftResults.add(passed);
        harness.log(
          'shift: gear ${harness.currentGear} ${_w(current.power)} vs ${_w(previous.power)} '
          '${passed ? 'harder' : 'no change'}',
        );
        _emit();
        previous = current;
      }
    } finally {
      await _restoreGear(startGear);
    }
  }

  /// Mean power/cadence over one settled window.
  Future<_Plateau> _plateau() async {
    var elapsed = 0;
    final powers = <int>[];
    final cadences = <int>[];
    while (elapsed < _ticksIn(plateauWindow)) {
      if (!await _tick()) {
        continue;
      }
      elapsed++;
      final p = _power;
      if (p != null) {
        powers.add(p);
      }
      final c = _cadence;
      if (c != null) {
        cadences.add(c);
      }
    }
    return _Plateau(_mean(powers), _mean(cadences));
  }

  /// A transition counts only if power rose while the rider held cadence —
  /// otherwise a spin-up would read as resistance.
  bool _transitionPassed(_Plateau current, _Plateau previous) {
    if (current.power <= previous.power) {
      return false;
    }
    if (previous.cadence <= 0) {
      return false;
    }
    final drift = (current.cadence - previous.cadence).abs() / previous.cadence;
    return drift <= cadenceDriftTolerance;
  }

  // ---------------------------------------------------------------- ticking
  /// Awaits one tick, refreshes the samples and updates pause bookkeeping.
  ///
  /// Returns false when the tick was swallowed by a pause — the caller must
  /// then not count it toward the current step's clock. Throws
  /// [_AbortedException] on cancel or when the pause outlives [pauseTimeout].
  Future<bool> _tick() async {
    _throwIfCancelled();
    await _sleep(tick);
    _throwIfCancelled();
    _power = harness.powerW.value;
    _cadence = harness.cadenceRpm.value;
    if (!_pauseArmed) {
      return true;
    }
    final rpm = _cadence ?? 0;
    if (_paused) {
      if (rpm >= baselineCadenceMin) {
        _paused = false;
        _pausedTicks = 0;
        _lowCadenceTicks = 0;
        harness.log('resumed: cadence back to ${rpm}rpm');
        _emit();
        return true;
      }
      _pausedTicks++;
      if (_pausedTicks >= _ticksIn(pauseTimeout)) {
        throw _AbortedException('paused for ${pauseTimeout.inSeconds}s without pedaling');
      }
      return false;
    }
    if (rpm < pauseCadenceBelow) {
      _lowCadenceTicks++;
      if (_lowCadenceTicks >= _ticksIn(pauseAfter)) {
        _paused = true;
        _pausedTicks = 0;
        harness.log('paused: cadence < $pauseCadenceBelow rpm for ${pauseAfter.inSeconds}s');
        _emit();
        return false;
      }
    } else {
      _lowCadenceTicks = 0;
    }
    return true;
  }

  void _throwIfCancelled() {
    if (_cancelled) {
      throw const _AbortedException('cancelled by the rider');
    }
  }

  // ---------------------------------------------------------------- restore
  /// 8. Always runs — on pass, fail, cancel and exception alike.
  Future<SelfTestResult> _finish({
    required SelfTestVerdict? verdict,
    required bool wasErg,
    required int? prevErgTarget,
    required int startGear,
  }) async {
    try {
      await _restoreGear(startGear);
      _restoreErg(wasErg: wasErg, prevErgTarget: prevErgTarget);
    } catch (e, s) {
      recordError(e, s, context: 'self-test restore');
    }
    final result = SelfTestResult(
      at: _now(),
      verdict: verdict ?? _verdictFromSteps(),
      ergStepsPassed: _ergResults.where((passed) => passed).length,
      ergStepsTotal: _ergTotal,
      shiftStepsPassed: _shiftResults.where((passed) => passed).length,
      shiftStepsTotal: _shiftTotal,
      vsMode: harness.vsModeName,
      protocol: harness.protocolName,
    );
    _result = result;
    _phase = SelfTestPhase.done;
    _paused = false;
    _currentErgTarget = null;
    _emit();
    harness.log('verdict: ${result.toBundleString()}');
    return result;
  }

  /// Restores the ERG state captured at the start of [run]. Idempotent: once
  /// the staircase has put it back there is nothing left to undo.
  void _restoreErg({required bool wasErg, required int? prevErgTarget}) {
    if (!_ergDirty) {
      return;
    }
    _ergDirty = false;
    final target = prevErgTarget ?? _p0;
    if (wasErg && target != null) {
      harness.setErgTarget(target);
      harness.log('restore: erg target ${target}W');
    } else {
      harness.exitErg();
      harness.log('restore: erg exited');
    }
  }

  /// Shifts back to the starting gear, one shift per tick. Deliberately uses
  /// the raw sleeper: a cancel must not stop us from putting the gear back.
  Future<void> _restoreGear(int startGear) async {
    if (!_gearDirty || harness.currentGear == startGear) {
      _gearDirty = false;
      return;
    }
    var shifts = 0;
    while (harness.currentGear != startGear && shifts < maxRestoreShifts) {
      if (harness.currentGear > startGear) {
        harness.shiftDown();
      } else {
        harness.shiftUp();
      }
      shifts++;
      await _sleep(tick);
    }
    _gearDirty = false;
    if (harness.currentGear != startGear) {
      harness.log('restore: gear stuck at ${harness.currentGear}, wanted $startGear');
      return;
    }
    harness.log('restore: gear ${harness.currentGear}');
  }

  // ---------------------------------------------------------------- verdict
  /// 7. A skipped ERG phase (`ergStepsTotal == 0`) leaves the verdict to the
  /// shift sweep alone.
  SelfTestVerdict _verdictFromSteps() {
    final ergPassed = _ergResults.where((passed) => passed).length;
    final shiftPassed = _shiftResults.where((passed) => passed).length;
    final bool? ergPass = _ergTotal == 0 ? null : ergPassed >= stepsToPass;
    final shiftPass = shiftPassed >= stepsToPass;
    if ((ergPass ?? true) && shiftPass) {
      return SelfTestVerdict.pass;
    }
    if (ergPass == true && !shiftPass) {
      return SelfTestVerdict.ergOkVsFail;
    }
    return SelfTestVerdict.noControl;
  }

  // ----------------------------------------------------------------- helpers
  void _emit() {
    _state.value = SelfTestState(
      phase: _phase,
      pausedForCadence: _paused,
      currentErgTarget: _currentErgTarget,
      ergStepResults: List.unmodifiable(_ergResults),
      shiftStepResults: List.unmodifiable(_shiftResults),
      result: _result,
    );
  }

  static Future<void> _realSleep(Duration d) => Future<void>.delayed(d);

  static int _ticksIn(Duration d) => (d.inMilliseconds / tick.inMilliseconds).ceil();

  static int _median(List<int> values) {
    if (values.isEmpty) {
      return 0;
    }
    final sorted = [...values]..sort();
    final middle = sorted.length ~/ 2;
    if (sorted.length.isOdd) {
      return sorted[middle];
    }
    return ((sorted[middle - 1] + sorted[middle]) / 2).round();
  }

  static double _mean(List<int> values) {
    if (values.isEmpty) {
      return 0;
    }
    return values.reduce((a, b) => a + b) / values.length;
  }

  static String _w(double value) => '${value.round()}W';
}

class _Plateau {
  const _Plateau(this.power, this.cadence);
  final double power;
  final double cadence;
}

class _AbortedException implements Exception {
  const _AbortedException(this.reason);
  final String reason;
  @override
  String toString() => 'SelfTestAborted: $reason';
}
