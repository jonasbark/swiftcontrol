import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:bike_control/bluetooth/devices/openbikecontrol/obp_mdns_backend.dart';
import 'package:bike_control/services/bonjour/bonjour_api.dart';
import 'package:bike_control/services/bonjour/bonjour_service_advertiser.dart';
import 'package:bike_control/utils/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prop/mdns/mdns_socket.dart';
import 'package:prop/mdns/service_advertiser.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../integration/harness/test_env.dart';
import 'recording_advertiser.dart';

/// Records register()/deallocate() calls instead of touching dnssd.dll, so
/// [BonjourServiceAdvertiser] can report "available" off Windows.
class _FakeBonjourApi implements BonjourApi {
  @override
  bool isAvailable = true;

  int registerCallCount = 0;

  @override
  Object register({required String name, required String type, required int port, required Uint8List txtRecord}) {
    registerCallCount++;
    return Object();
  }

  @override
  void deallocate(Object handle) {}
}

/// No-op transport for [ResponderServiceAdvertiser] — records nothing, binds
/// no real socket, so [OpenBikeControlMdnsEmulator.startServer] can run
/// against a real responder instance without touching the network.
class _FakeMdnsSocket implements MdnsSocket {
  final _incoming = StreamController<MdnsPacket>.broadcast();

  @override
  Stream<MdnsPacket> get incoming => _incoming.stream;

  @override
  void sendMulticast(Uint8List data, {InternetAddress? via}) {}

  @override
  void sendUnicast(Uint8List data, InternetAddress to, int port) {}

  @override
  InternetAddress? egressInterfaceFor(InternetAddress source) => null;

  @override
  bool get holdsMulticastLock => false;

  @override
  Future<void> close() async {
    await _incoming.close();
  }
}

Future<void> main() async {
  final env = await IntegrationEnv.setUp();
  late RecordingAdvertiser instanceAdvertiser;

  setUp(() async {
    env.mdns.reset();
    SharedPreferences.setMockInitialValues({});
    core.settings.prefs = await SharedPreferences.getInstance();
    instanceAdvertiser = RecordingAdvertiser();
    ServiceAdvertiser.instance = instanceAdvertiser;
  });

  tearDown(() async {
    await core.obpMdnsEmulator.stopServer();
    ServiceAdvertiser.instance = NsdServiceAdvertiser();
    // These test seams are opt-in per test; reset them so a test that forces
    // the Windows branch or injects a fake Bonjour advertiser cannot leak
    // into the next test in this file.
    core.obpMdnsEmulator.debugAdvertiserOverride = null;
    core.obpMdnsEmulator.debugBonjourFactory = null;
    core.obpMdnsEmulator.debugIsWindows = null;
  });

  test('platformDefault registers through ServiceAdvertiser.instance', () async {
    await core.obpMdnsEmulator.startServer();
    expect(instanceAdvertiser.services, hasLength(1));
    expect(env.mdns.registrations, isEmpty);
    expect(core.obpMdnsEmulator.activeBackend, ObpMdnsBackend.platformDefault);
  });

  // This test host is not Windows, so resolveAdvertiser never reaches the
  // Bonjour branch regardless of BonjourServiceAdvertiser.isAvailable — the
  // osResponder path always resolves through nsd here.
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

  group('resolveAdvertiser', () {
    test('platformDefault resolves to ServiceAdvertiser.instance', () {
      final result = core.obpMdnsEmulator.resolveAdvertiser(ObpMdnsBackend.platformDefault);
      expect(result.advertiser, same(instanceAdvertiser));
      expect(result.resolved, ObpMdnsBackend.platformDefault);
    });

    test('osResponder on a non-Windows host resolves to an nsd advertiser', () {
      final result = core.obpMdnsEmulator.resolveAdvertiser(ObpMdnsBackend.osResponder);
      expect(result.advertiser, isA<NsdServiceAdvertiser>());
      expect(result.resolved, ObpMdnsBackend.osResponder);
    });

    test('debugAdvertiserOverride wins and resolves to the requested backend verbatim', () {
      final override = RecordingAdvertiser();
      core.obpMdnsEmulator.debugAdvertiserOverride = override;
      final result = core.obpMdnsEmulator.resolveAdvertiser(ObpMdnsBackend.osResponder);
      expect(result.advertiser, same(override));
      expect(result.resolved, ObpMdnsBackend.osResponder);
    });

    test('Windows without Bonjour installed falls back to platformDefault', () {
      // No debugBonjourFactory: the real BonjourServiceAdvertiser() this
      // constructs reports isAvailable == false on this (non-Windows) host,
      // exactly like a Windows machine without Bonjour installed does.
      core.obpMdnsEmulator.debugIsWindows = () => true;
      final result = core.obpMdnsEmulator.resolveAdvertiser(ObpMdnsBackend.osResponder);
      expect(result.advertiser, same(instanceAdvertiser),
          reason: 'the record ends up served by ServiceAdvertiser.instance, not an OS responder');
      expect(result.resolved, ObpMdnsBackend.platformDefault,
          reason: 'osResponder degrades to platformDefault so activeBackend never lies about what serves the record');
    });

    test('Windows with Bonjour available resolves osResponder to the Bonjour advertiser', () {
      final fakeBonjour = BonjourServiceAdvertiser(api: _FakeBonjourApi());
      core.obpMdnsEmulator.debugIsWindows = () => true;
      core.obpMdnsEmulator.debugBonjourFactory = () => fakeBonjour;
      final result = core.obpMdnsEmulator.resolveAdvertiser(ObpMdnsBackend.osResponder);
      expect(result.advertiser, same(fakeBonjour));
      expect(result.resolved, ObpMdnsBackend.osResponder);
    });
  });

  group('advertisedHostname', () {
    test('null while stopped', () {
      expect(core.obpMdnsEmulator.advertisedHostname, isNull);
    });

    test('platformDefault with an in-process responder reports the responder\'s hostLabel', () async {
      final responder = ResponderServiceAdvertiser(
        socketFactory: (address) async => _FakeMdnsSocket(),
        hostLabel: 'bikecontrol-test',
      );
      ServiceAdvertiser.instance = responder;
      await core.obpMdnsEmulator.startServer();
      expect(core.obpMdnsEmulator.advertisedHostname, 'bikecontrol-test.local');
    });

    test('osResponder (nsd) reports the machine hostname', () async {
      await core.settings.setObpMdnsBackend(ObpMdnsBackend.osResponder);
      await core.obpMdnsEmulator.startServer();
      expect(core.obpMdnsEmulator.advertisedHostname, '${Platform.localHostname}.local');
    });

    test('Windows osResponder degraded to platformDefault reports the fallback advertiser\'s hostname, not the machine name', () async {
      final responder = ResponderServiceAdvertiser(
        socketFactory: (address) async => _FakeMdnsSocket(),
        hostLabel: 'bikecontrol-fallback',
      );
      ServiceAdvertiser.instance = responder;
      core.obpMdnsEmulator.debugIsWindows = () => true;
      await core.settings.setObpMdnsBackend(ObpMdnsBackend.osResponder);

      await core.obpMdnsEmulator.startServer();

      expect(core.obpMdnsEmulator.activeBackend, ObpMdnsBackend.platformDefault);
      expect(core.obpMdnsEmulator.advertisedHostname, 'bikecontrol-fallback.local');
    });

    test('Windows osResponder with Bonjour available reports the machine hostname', () async {
      final fakeBonjour = BonjourServiceAdvertiser(api: _FakeBonjourApi());
      core.obpMdnsEmulator.debugIsWindows = () => true;
      core.obpMdnsEmulator.debugBonjourFactory = () => fakeBonjour;
      await core.settings.setObpMdnsBackend(ObpMdnsBackend.osResponder);

      await core.obpMdnsEmulator.startServer();

      expect(core.obpMdnsEmulator.activeBackend, ObpMdnsBackend.osResponder);
      expect(core.obpMdnsEmulator.advertisedHostname, '${Platform.localHostname}.local');
    });
  });
}
