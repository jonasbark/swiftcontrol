import 'package:bike_control/services/trainer_self_test/self_test_harness.dart';
import 'package:bike_control/utils/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    core.settings.prefs = await SharedPreferences.getInstance();
  });

  test('self-test result json is stored per trainer key', () async {
    expect(core.settings.getSelfTestResultJson('KICKR CORE'), isNull);
    await core.settings.setSelfTestResultJson('KICKR CORE', '{"v":1}');
    expect(core.settings.getSelfTestResultJson('KICKR CORE'), '{"v":1}');
    expect(core.settings.getSelfTestResultJson('Other'), isNull);
  });
}
