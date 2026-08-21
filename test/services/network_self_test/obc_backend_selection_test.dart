import 'package:bike_control/bluetooth/devices/openbikecontrol/obp_mdns_backend.dart';
import 'package:bike_control/utils/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prop/mdns/service_advertiser.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../integration/harness/test_env.dart';

/// Records register() calls without any real sockets.
class _RecordingAdvertiser implements ServiceAdvertiser {
  final services = <AdvertisedService>[];
  @override
  Future<ServiceAdvertisement> register(AdvertisedService service) async {
    services.add(service);
    return _Registration(this, service);
  }
}

class _Registration implements ServiceAdvertisement {
  _Registration(this.owner, this.service);
  final _RecordingAdvertiser owner;
  final AdvertisedService service;
  @override
  Future<void> unregister() async => owner.services.remove(service);
}

Future<void> main() async {
  final env = await IntegrationEnv.setUp();
  late _RecordingAdvertiser instanceAdvertiser;

  setUp(() async {
    env.mdns.reset();
    SharedPreferences.setMockInitialValues({});
    core.settings.prefs = await SharedPreferences.getInstance();
    instanceAdvertiser = _RecordingAdvertiser();
    ServiceAdvertiser.instance = instanceAdvertiser;
  });

  tearDown(() async {
    await core.obpMdnsEmulator.stopServer();
    ServiceAdvertiser.instance = NsdServiceAdvertiser();
  });

  test('platformDefault registers through ServiceAdvertiser.instance', () async {
    await core.obpMdnsEmulator.startServer();
    expect(instanceAdvertiser.services, hasLength(1));
    expect(env.mdns.registrations, isEmpty);
    expect(core.obpMdnsEmulator.activeBackend, ObpMdnsBackend.platformDefault);
  });

  // On this (non-Windows) test host BonjourServiceAdvertiser.isAvailable is
  // false, so Platform.isWindows is false anyway and the os path is nsd.
  test('osResponder registers through an emulator-owned nsd advertiser', () async {
    await core.settings.setObpMdnsBackend(ObpMdnsBackend.osResponder);
    await core.obpMdnsEmulator.startServer();
    expect(env.mdns.registrations, hasLength(1),
        reason: 'the OS responder path goes through the nsd plugin');
    expect(instanceAdvertiser.services, isEmpty);
    expect(core.obpMdnsEmulator.activeBackend, ObpMdnsBackend.osResponder);

    await core.obpMdnsEmulator.stopServer();
    expect(env.mdns.registrations, isEmpty, reason: 'unregisters through the same advertiser');
  });

  test('stopServer resets activeBackend', () async {
    await core.obpMdnsEmulator.startServer();
    await core.obpMdnsEmulator.stopServer();
    expect(core.obpMdnsEmulator.activeBackend, ObpMdnsBackend.platformDefault);
  });
}
