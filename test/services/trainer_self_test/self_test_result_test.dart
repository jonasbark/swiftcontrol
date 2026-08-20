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
