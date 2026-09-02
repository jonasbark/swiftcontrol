import 'package:bike_control/services/trainer_self_test/self_test_engine.dart';
import 'package:bike_control/services/trainer_self_test/self_test_result.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_self_test_harness.dart';

Future<(SelfTestResult, FakeSelfTestHarness)> runScenario(void Function(FakeSelfTestHarness) configure) async {
  final harness = FakeSelfTestHarness();
  configure(harness);
  final engine = SelfTestEngine(
    harness: harness,
    sleep: (d) async {
      harness.publishTick();
    }, // 1 call == 1 tick
    now: () => DateTime(2026, 8, 20),
  );
  final result = await engine.run();
  return (result, harness);
}

void main() {
  test('obedient trainer passes both phases', () async {
    final (r, h) = await runScenario((_) {});
    expect(r.verdict, SelfTestVerdict.pass);
    expect(r.ergStepsPassed, 3);
    expect(r.shiftStepsPassed, greaterThanOrEqualTo(2));
    expect(h.gear, 12, reason: 'gear restored');
    expect(h.ergMode, isFalse, reason: 'erg exited after test');
  });

  test('deaf trainer yields noControl', () async {
    final (r, _) = await runScenario((h) {
      h.obeysErg = false;
      h.obeysShift = false;
    });
    expect(r.verdict, SelfTestVerdict.noControl);
  });

  test('erg-only trainer yields ergOkVsFail', () async {
    final (r, _) = await runScenario((h) => h.obeysShift = false);
    expect(r.verdict, SelfTestVerdict.ergOkVsFail);
  });

  test('shift-only trainer yields vsOkErgFail, not noControl', () async {
    // The Van Rysel HT RCR shape: virtual shifting lands over Zwift Sync but
    // ERG does not. Reporting "no control" here sends a rider off to change a
    // protocol that was already driving the thing they came for.
    final (r, _) = await runScenario((h) => h.obeysErg = false);
    expect(r.verdict, SelfTestVerdict.vsOkErgFail);
  });

  test('no power samples yields noData within precheck window', () async {
    final harness = FakeSelfTestHarness();
    final engine = SelfTestEngine(harness: harness, sleep: (_) async {}, now: () => DateTime(2026, 8, 20));
    final r = await engine.run();
    expect(r.verdict, SelfTestVerdict.noData);
  });

  test('trainer without power-target support skips ERG and can still pass', () async {
    final (r, _) = await runScenario((h) => h.supportsPowerTarget = false);
    expect(r.ergStepsTotal, 0);
    expect(r.verdict, SelfTestVerdict.pass);
  });

  test('cadence-less trainer completes the test instead of aborting', () async {
    // Some firmwares ship with cadence disabled, so the field never arrives.
    // The baseline used to wait for 40 rpm that could never come, the pause
    // watchdog then read the silence as a rider who had stopped, and the run
    // aborted — on exactly the trainers whose riders most need a verdict.
    final (r, h) = await runScenario((h) => h.reportsCadence = false);
    expect(r.verdict, SelfTestVerdict.pass);
    expect(r.shiftStepsTotal, 3, reason: 'the sweep must still be scored');
    expect(h.gear, 12, reason: 'gear restored');
    // Scoring on power alone is a caveat on the verdict, so the rider is told:
    // the result carries it and the card renders it.
    expect(r.cadenceless, isTrue);
  });

  test('a cadence-reporting trainer produces a result that is not marked cadence-less', () async {
    final (r, _) = await runScenario((_) {});
    expect(r.cadenceless, isFalse);
  });

  test('cadence-less trainer that ignores commands still yields noControl', () async {
    // Scoring the sweep on power alone must not turn a deaf trainer into a pass.
    final (r, _) = await runScenario((h) {
      h.reportsCadence = false;
      h.obeysErg = false;
      h.obeysShift = false;
    });
    expect(r.verdict, SelfTestVerdict.noControl);
  });

  test('cadence-less rider who stops pedaling still pauses and aborts', () async {
    // Without cadence the coasting watchdog reads power instead — otherwise a
    // rider who stops would have every remaining step scored as "no response".
    final harness = FakeSelfTestHarness()
      ..reportsCadence = false
      ..supportsPowerTarget = false // skip ERG: it pins power to the target
      ..obeysShift = false;
    var ticks = 0;
    final engine = SelfTestEngine(
      harness: harness,
      now: () => DateTime(2026, 8, 20),
      sleep: (_) async {
        ticks++;
        if (ticks > 20) harness.riderPower = 0; // stop pedaling mid-test
        harness.publishTick();
      },
    );
    final r = await engine.run();
    expect(r.verdict, SelfTestVerdict.aborted);
  });

  test('coasting rider pauses then aborts', () async {
    final harness = FakeSelfTestHarness();
    var ticks = 0;
    final engine = SelfTestEngine(
      harness: harness,
      now: () => DateTime(2026, 8, 20),
      sleep: (_) async {
        ticks++;
        if (ticks > 20) harness.riderCadence = 0; // stop pedaling mid-test
        harness.publishTick();
      },
    );
    final r = await engine.run();
    expect(r.verdict, SelfTestVerdict.aborted);
  });

  test('cancel mid-run aborts and restores', () async {
    final harness = FakeSelfTestHarness();
    late SelfTestEngine engine;
    var ticks = 0;
    engine = SelfTestEngine(
      harness: harness,
      now: () => DateTime(2026, 8, 20),
      sleep: (_) async {
        ticks++;
        if (ticks == 30) engine.cancel();
        harness.publishTick();
      },
    );
    final r = await engine.run();
    expect(r.verdict, SelfTestVerdict.aborted);
    expect(harness.ergMode, isFalse);
    expect(harness.gear, 12);
  });

  test('rider already in manual ERG: sweep still runs in SIM, ERG restored at finish', () async {
    final (r, h) = await runScenario((h) => h.setErgTarget(210));
    expect(r.verdict, SelfTestVerdict.pass);
    expect(r.shiftStepsPassed, 3, reason: 'the sweep must run in SIM, not pinned by manual ERG');
    expect(h.ergMode, isTrue, reason: 'rider ERG restored');
    expect(h.ergTarget, 210, reason: 'rider ERG target restored');
    expect(h.gear, 12, reason: 'gear restored');
  });

  test('rider who was not in ERG ends out of ERG', () async {
    final (_, h) = await runScenario((_) {});
    expect(h.ergMode, isFalse);
    expect(h.ergTarget, isNull);
  });

  test('gear headroom: sweep from near maxGear shifts down first and restores', () async {
    final (r, h) = await runScenario((h) => h.gear = 24);
    expect(r.verdict, SelfTestVerdict.pass);
    expect(h.gear, 24);
  });

  test('tiny gear range (maxGear 2) completes instead of shifting down forever', () async {
    final harness = _FlooredGearHarness()
      ..maxGear = 2
      ..gear = 2;
    final engine = SelfTestEngine(
      harness: harness,
      sleep: (_) async => harness.publishTick(),
      now: () => DateTime(2026, 8, 20),
    );
    final r = await engine.run();
    expect(r.verdict, isNot(SelfTestVerdict.aborted), reason: 'must not hang or bail out');
    expect(harness.gear, 2, reason: 'gear restored');
    expect(harness.logLines, contains('shift: headroom stalled at gear 1'));
  });

  test('trainer that refuses to shift terminates with a sensible verdict', () async {
    final harness = _RefusingShiftHarness()..gear = 24;
    final engine = SelfTestEngine(
      harness: harness,
      sleep: (_) async => harness.publishTick(),
      now: () => DateTime(2026, 8, 20),
    );
    final r = await engine.run();
    expect(r.verdict, SelfTestVerdict.ergOkVsFail, reason: 'ERG obeyed, shifting did not');
    expect(r.shiftStepsPassed, 0);
    expect(harness.gear, 24, reason: 'never moved, nothing to restore');
  });

  test('ERG-less trainer: rider ERG is dropped for the sweep and restored at finish', () async {
    final (r, h) = await runScenario((h) {
      h.supportsPowerTarget = false;
      h.setErgTarget(210);
    });
    expect(r.verdict, SelfTestVerdict.pass);
    expect(r.ergStepsTotal, 0);
    expect(r.shiftStepsPassed, 3, reason: 'plateaus must be measured in SIM, not ERG-pinned');
    expect(h.ergMode, isTrue);
    expect(h.ergTarget, 210, reason: 'rider ERG restored');
  });

  test('upstream dropout mid-staircase aborts instead of reporting noControl', () async {
    final harness = FakeSelfTestHarness();
    var ticks = 0;
    final engine = SelfTestEngine(
      harness: harness,
      now: () => DateTime(2026, 8, 20),
      sleep: (_) async {
        ticks++;
        if (ticks == 16) harness.upstreamConnected = false; // BLE drops mid-ERG
        harness.publishTick();
      },
    );
    final r = await engine.run();
    expect(r.verdict, SelfTestVerdict.aborted);
    expect(harness.ergMode, isFalse, reason: 'restore ran despite the dropout');
    expect(harness.gear, 12);
  });
  test('a refused ERG exit is logged, not fatal — the run keeps its score', () async {
    final harness = _RefusingErgExitHarness();
    final engine = SelfTestEngine(
      harness: harness,
      sleep: (_) async => harness.publishTick(),
      now: () => DateTime(2026, 8, 20),
    );
    final r = await engine.run();
    expect(r.verdict, SelfTestVerdict.ergOkVsFail, reason: 'scored, not downgraded to aborted');
    expect(r.ergStepsPassed, 3);
    expect(harness.gear, 12, reason: 'gear restore still ran');
  });
}

/// Mirrors prop's clamp: the trainer will not shift below its lowest gear.
class _FlooredGearHarness extends FakeSelfTestHarness {
  @override
  void shiftDown() {
    if (gear > 1) super.shiftDown();
  }
}

/// A trainer that acknowledges shift commands but never changes gear.
class _RefusingShiftHarness extends FakeSelfTestHarness {
  @override
  void shiftUp() {}
  @override
  void shiftDown() {}
}

/// A trainer whose control point rejects the ERG exit — the write throws and
/// the mode stays put.
class _RefusingErgExitHarness extends FakeSelfTestHarness {
  @override
  void exitErg() => throw StateError('control point refused');
}
