import 'package:bike_control/bluetooth/devices/openbikecontrol/obp_mdns_backend.dart';
import 'package:bike_control/utils/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    core.settings.prefs = await SharedPreferences.getInstance();
  });

  test('backend defaults to platformDefault and round-trips', () async {
    expect(core.settings.getObpMdnsBackend(), ObpMdnsBackend.platformDefault);
    await core.settings.setObpMdnsBackend(ObpMdnsBackend.osResponder);
    expect(core.settings.getObpMdnsBackend(), ObpMdnsBackend.osResponder);
  });

  test('an unknown stored value degrades to platformDefault', () async {
    SharedPreferences.setMockInitialValues({'openbikeprotocol_mdns_backend': 'quantum'});
    core.settings.prefs = await SharedPreferences.getInstance();
    expect(core.settings.getObpMdnsBackend(), ObpMdnsBackend.platformDefault);
  });

  test('network self-test json round-trips', () async {
    expect(core.settings.getNetworkSelfTestResultJson(), isNull);
    await core.settings.setNetworkSelfTestResultJson('{"at":"2026-08-21T10:00:00.000"}');
    expect(core.settings.getNetworkSelfTestResultJson(), contains('2026-08-21'));
  });
}
