import 'package:bike_control/bluetooth/devices/openbikecontrol/obp_mdns_backend.dart';
import 'package:bike_control/services/bonjour/bonjour_service_advertiser.dart';
import 'package:bike_control/services/network_self_test/network_fixes.dart';
import 'package:bike_control/utils/core.dart';
import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:nsd_platform_interface/nsd_platform_interface.dart';
import 'package:prop/mdns/service_advertiser.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../integration/harness/fake_nsd_platform.dart';
import '../../integration/harness/test_env.dart';
import 'fake_bonjour_api.dart';
import 'recording_advertiser.dart';

/// Throws once from register(), then behaves like the real fake — models a
/// transient nsd registration failure so [switchObpBackend]'s rollback path
/// can be exercised without touching the real nsd plugin.
class _ThrowOnceRegisterNsdPlatform extends FakeNsdPlatform {
  bool _thrown = false;

  @override
  Future<Registration> register(Service service) async {
    if (!_thrown) {
      _thrown = true;
      throw Exception('simulated nsd register failure');
    }
    return super.register(service);
  }
}

Future<void> main() async {
  final env = await IntegrationEnv.setUp();
  late RecordingAdvertiser instanceAdvertiser;

  setUp(() async {
    env.mdns.reset();
    NsdPlatformInterface.instance = env.mdns;
    SharedPreferences.setMockInitialValues({});
    core.settings.prefs = await SharedPreferences.getInstance();
    instanceAdvertiser = RecordingAdvertiser();
    ServiceAdvertiser.instance = instanceAdvertiser;
  });

  tearDown(() async {
    core.obpMdnsEmulator.isConnected.value = false;
    await core.obpMdnsEmulator.stopServer();
    ServiceAdvertiser.instance = NsdServiceAdvertiser();
    NsdPlatformInterface.instance = env.mdns;
    core.obpMdnsEmulator.debugBonjourFactory = null;
    core.obpMdnsEmulator.debugIsWindows = null;
  });

  group('switchObpBackend', () {
    test('switching to osResponder re-registers via the nsd fake and persists the pref', () async {
      final ok = await switchObpBackend(ObpMdnsBackend.osResponder);

      expect(ok, isTrue);
      expect(core.settings.getObpMdnsBackend(), ObpMdnsBackend.osResponder);
      expect(env.mdns.registrations, hasLength(1), reason: 'the OS responder path goes through the nsd plugin');
      expect(core.obpMdnsEmulator.activeBackend, ObpMdnsBackend.osResponder);
    });

    test('a failing start restores the pref and returns false', () async {
      await core.obpMdnsEmulator.startServer(); // running on platformDefault
      NsdPlatformInterface.instance = _ThrowOnceRegisterNsdPlatform();

      final ok = await switchObpBackend(ObpMdnsBackend.osResponder);

      expect(ok, isFalse);
      expect(core.settings.getObpMdnsBackend(), ObpMdnsBackend.platformDefault);
    });

    test('a failing start leaves the emulator started again on the old backend', () async {
      await core.obpMdnsEmulator.startServer(); // running on platformDefault
      NsdPlatformInterface.instance = _ThrowOnceRegisterNsdPlatform();

      await switchObpBackend(ObpMdnsBackend.osResponder);

      expect(core.obpMdnsEmulator.isStarted.value, isTrue);
      expect(core.obpMdnsEmulator.activeBackend, ObpMdnsBackend.platformDefault);
    });

    // "Register through Bonjour" on a Windows box without Bonjour: the start
    // itself succeeds (resolveAdvertiser degrades to platformDefault), so the
    // old "did startServer throw?" test was blind to it — the pref was left
    // at osResponder, the page re-ran with the identical result, and row 6
    // (keyed on activeBackend) offered no way back.
    test('a degraded switch (Windows without Bonjour) is a failed switch: pref restored, returns false', () async {
      await core.obpMdnsEmulator.startServer(); // running on platformDefault
      core.obpMdnsEmulator.debugIsWindows = () => true;
      core.obpMdnsEmulator.debugBonjourFactory = () => BonjourServiceAdvertiser(api: FakeBonjourApi(isAvailable: false));

      final ok = await switchObpBackend(ObpMdnsBackend.osResponder);

      expect(ok, isFalse);
      expect(core.settings.getObpMdnsBackend(), ObpMdnsBackend.platformDefault, reason: 'the previous pref is restored');
      expect(core.obpMdnsEmulator.isStarted.value, isTrue, reason: 'restarted on the restored pref');
      expect(core.obpMdnsEmulator.activeBackend, ObpMdnsBackend.platformDefault);
      expect(env.mdns.registrations, isEmpty, reason: 'nsd is never the Windows OS backend');
      expect(instanceAdvertiser.services, hasLength(1));
    });

    test('refuses while the trainer app is connected: no restart, pref untouched', () async {
      await core.obpMdnsEmulator.startServer(); // running on platformDefault
      core.obpMdnsEmulator.isConnected.value = true;
      final registeredBefore = instanceAdvertiser.services.toList();

      final ok = await switchObpBackend(ObpMdnsBackend.osResponder);

      expect(ok, isFalse);
      expect(core.settings.getObpMdnsBackend(), ObpMdnsBackend.platformDefault);
      expect(core.obpMdnsEmulator.isConnected.value, isTrue, reason: 'the live connection was not dropped');
      expect(core.obpMdnsEmulator.activeBackend, ObpMdnsBackend.platformDefault);
      expect(instanceAdvertiser.services, equals(registeredBefore), reason: 'the running registration was not touched');
      expect(env.mdns.registrations, isEmpty);
    });
  });
}
