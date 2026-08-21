import 'dart:io';

import 'package:bike_control/services/debug_diagnostics.dart';
import 'package:bike_control/services/mdns_discovery_scan.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prop/utils/advertised_service_registry.dart';
import 'package:prop/utils/network_address.dart';

void main() {
  test('toText renders every section with the expected markers', () {
    final diag = DebugDiagnostics(
      advertised: const [
        AdvertisedRecord(
          name: 'BikeControl',
          type: '_openbikecontrol._tcp',
          port: 36867,
          address: '192.168.1.9',
          txt: {'version': '0x01', 'name': 'BikeControl', 'id': '1337'},
        ),
      ],
      backend: 'responder',
      hostLabel: 'bikecontrol-3f2a',
      holdsMulticastLock: true,
      discovered: const [
        DiscoveredMdnsService(
          type: '_wahoo-fitness-tnp._tcp',
          name: 'BikeControl',
          host: '192.168.1.9',
          port: 36867,
          txt: {},
          isSelf: true,
        ),
      ],
      discoveryRan: true,
      addressReport: AddressPickReport(
        chosen: InternetAddress('192.168.1.9'),
        candidates: const [
          AddressCandidate(interfaceName: 'en0', address: '192.168.1.9', score: 40, isVirtual: false),
          AddressCandidate(interfaceName: 'utun0', address: '10.2.0.2', score: -60, isVirtual: true),
        ],
      ),
      servers: const [
        TcpServerInfo(label: 'OpenBikeControl', port: 36867, listening: true, hasClient: true),
      ],
      permissions: const PermissionsSnapshot(
        localNetwork: LocalNetworkStatus.granted,
      ),
    );

    final text = diag.toText();

    expect(text, contains('Advertised by this device'));
    expect(text, contains('_openbikecontrol._tcp "BikeControl" 192.168.1.9:36867'));
    // TXT entries are rendered alphabetically by key.
    expect(text, contains('txt: id=1337, name=BikeControl, version=0x01'));
    expect(text, contains('host: bikecontrol-3f2a.local'));
    expect(text, contains('multicast-lock: held'));
    expect(text, contains('(this device)'));
    expect(text, contains('en0/192.168.1.9 = 40 (advertised)'));
    expect(text, contains('utun0/10.2.0.2 = -60 (virtual)'));
    expect(text, contains('OpenBikeControl :36867 listening · 1 client'));
    expect(text, contains('local-network=granted'));
  });

  test('toText marks discovery as skipped when it did not run', () {
    final diag = DebugDiagnostics(
      advertised: const [],
      backend: 'nsd',
      hostLabel: null,
      holdsMulticastLock: false,
      discovered: const [],
      discoveryRan: false,
      addressReport: const AddressPickReport(chosen: null, candidates: []),
      servers: const [],
      permissions: const PermissionsSnapshot(localNetwork: null),
    );

    expect(diag.toText(), contains('Discovered on network:'));
    expect(diag.toText(), contains('(skipped)'));
  });

  group('VPN line', () {
    DebugDiagnostics withCandidates(List<AddressCandidate> candidates) => DebugDiagnostics(
      advertised: const [],
      backend: 'nsd',
      hostLabel: null,
      holdsMulticastLock: false,
      discovered: const [],
      discoveryRan: true,
      addressReport: AddressPickReport(chosen: InternetAddress('192.168.1.9'), candidates: candidates),
      servers: const [],
      permissions: const PermissionsSnapshot(localNetwork: null),
    );

    test('names the tunnel interface when a VPN carries a routable IPv4', () {
      // The real support bundle: mDNS fine, both servers listening, no client.
      final text = withCandidates(const [
        AddressCandidate(interfaceName: 'pdp_ip0', address: '192.0.0.2', score: 1, isVirtual: false),
        AddressCandidate(interfaceName: 'en0', address: '10.70.0.15', score: 30, isVirtual: false),
        AddressCandidate(interfaceName: 'utun4', address: '10.2.0.2', score: -70, isVirtual: true),
      ]).toText();

      expect(text, contains('VPN: likely active — utun4/10.2.0.2'));
      expect(text, contains('blocks inbound LAN connections'));
    });

    test('reports none when only physical and non-VPN virtual interfaces exist', () {
      // bridge100 is the Personal Hotspot / Internet Sharing bridge and
      // v4-rmnet the 464XLAT CLAT device: both "virtual", neither a VPN.
      final text = withCandidates(const [
        AddressCandidate(interfaceName: 'en0', address: '192.168.1.9', score: 40, isVirtual: false),
        AddressCandidate(interfaceName: 'bridge100', address: '172.20.10.1', score: -80, isVirtual: true),
        AddressCandidate(interfaceName: 'v4-rmnet_data2', address: '192.0.0.8', score: 1, isVirtual: true),
        AddressCandidate(interfaceName: 'docker0', address: '172.17.0.1', score: -80, isVirtual: true),
      ]).toText();

      expect(text, contains('VPN: none detected'));
    });

    test('flags a mesh VPN in the CGNAT range as usually harmless', () {
      final text = withCandidates(const [
        AddressCandidate(interfaceName: 'en0', address: '192.168.1.9', score: 40, isVirtual: false),
        AddressCandidate(interfaceName: 'utun8', address: '100.76.35.113', score: -90, isVirtual: true),
      ]).toText();

      expect(text, contains('VPN: likely active — utun8/100.76.35.113'));
      expect(text, contains('usually harmless'));
    });

    test('matches Windows adapter FriendlyNames, which are not unix device names', () {
      final text = withCandidates(const [
        AddressCandidate(interfaceName: 'Wi-Fi', address: '192.168.1.9', score: 40, isVirtual: false),
        AddressCandidate(interfaceName: 'ProtonVPN TUN', address: '10.2.0.2', score: 30, isVirtual: false),
      ]).toText();

      expect(text, contains('VPN: likely active — ProtonVPN TUN/10.2.0.2'));
    });

    test('ignores idle Apple tunnels that only ever carry a link-local IPv4', () {
      final text = withCandidates(const [
        AddressCandidate(interfaceName: 'en0', address: '192.168.1.9', score: 40, isVirtual: false),
        AddressCandidate(interfaceName: 'utun2', address: '169.254.10.20', score: -99, isVirtual: true),
      ]).toText();

      expect(text, contains('VPN: none detected'));
    });
  });
}
