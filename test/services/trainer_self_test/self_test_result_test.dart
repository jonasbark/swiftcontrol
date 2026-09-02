import 'package:bike_control/services/trainer_self_test/self_test_result.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final result = SelfTestResult(
    at: DateTime(2026, 8, 20),
    verdict: SelfTestVerdict.ergOkVsFail,
    ergStepsPassed: 3, ergStepsTotal: 3,
    shiftStepsPassed: 0, shiftStepsTotal: 3,
    vsMode: 'targetPower', protocol: 'ftms',
  );

  test('bundle string is compact and space-free', () {
    expect(result.toBundleString(), 'ERG_OK_VS_FAIL,2026-08-20,a:3/3,b:0/3,targetPower');
    expect(result.toBundleString().contains(' '), isFalse);
  });

  test('the shifting-works-ERG-does-not verdict has its own bundle label', () {
    final result = SelfTestResult(
      at: DateTime(2026, 8, 22),
      verdict: SelfTestVerdict.vsOkErgFail,
      ergStepsPassed: 1,
      ergStepsTotal: 3,
      shiftStepsPassed: 2,
      shiftStepsTotal: 3,
      vsMode: 'targetPower',
      protocol: 'zwiftHub',
    );
    expect(result.toBundleString(), 'VS_OK_ERG_FAIL,2026-08-22,a:1/3,b:2/3,targetPower');
  });

  test('a cadence-less run is marked in the bundle string and survives a round-trip', () {
    // The shift phase was scored without the cadence cross-check, so a bundle
    // reader has to be able to see that — and so does the rider (see the card).
    final noCadence = SelfTestResult(
      at: DateTime(2026, 9, 1),
      verdict: SelfTestVerdict.pass,
      ergStepsPassed: 3,
      ergStepsTotal: 3,
      shiftStepsPassed: 3,
      shiftStepsTotal: 3,
      vsMode: 'trackResistance',
      protocol: 'ftms',
      cadenceless: true,
    );
    expect(noCadence.toBundleString(), 'PASS,2026-09-01,a:3/3,b:3/3,trackResistance,no-cadence');
    expect(SelfTestResult.tryParse(noCadence.toJsonString())?.cadenceless, isTrue);
  });

  test('a result stored before the cadence-less flag existed still parses', () {
    // Older stored JSON has no `cadenceless` key at all.
    final legacy = SelfTestResult.tryParse(
      '{"at":"2026-08-20T00:00:00.000","verdict":"pass","ergStepsPassed":3,"ergStepsTotal":3,'
      '"shiftStepsPassed":3,"shiftStepsTotal":3,"vsMode":"targetPower","protocol":"ftms"}',
    );
    expect(legacy, isNotNull);
    expect(legacy!.cadenceless, isFalse);
  });

  test('skipped ERG phase renders a:n/a', () {
    final skipped = SelfTestResult(
      at: DateTime(2026, 8, 20), verdict: SelfTestVerdict.pass,
      ergStepsPassed: 0, ergStepsTotal: 0,
      shiftStepsPassed: 3, shiftStepsTotal: 3,
      vsMode: 'trackResistance', protocol: 'fec',
    );
    expect(skipped.toBundleString(), 'PASS,2026-08-20,a:n/a,b:3/3,trackResistance');
  });

  test('json roundtrip', () {
    final back = SelfTestResult.fromJson(result.toJson());
    expect(back.verdict, result.verdict);
    expect(back.at, result.at);
    expect(back.shiftStepsTotal, 3);
    expect(SelfTestResult.tryParse(result.toJsonString())!.protocol, 'ftms');
    expect(SelfTestResult.tryParse(null), isNull);
    expect(SelfTestResult.tryParse('garbage'), isNull);
  });
}
