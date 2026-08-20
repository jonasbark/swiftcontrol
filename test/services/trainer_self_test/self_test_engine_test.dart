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
}
