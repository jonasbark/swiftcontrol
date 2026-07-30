import 'dart:io';

import 'package:bike_control/services/debug_diagnostics.dart';
import 'package:bike_control/services/mdns_discovery_scan.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prop/mdns/mdns_responder.dart' show MdnsQueryLogEntry;
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
        localNetworkInferred: true,
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
    expect(text, contains('ios-local-network=inferred-ok'));
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
      permissions: const PermissionsSnapshot(localNetworkInferred: null),
    );

    expect(diag.toText(), contains('Discovered on network:'));
    expect(diag.toText(), contains('(skipped)'));
  });

  group('mDNS queries received', () {
    DebugDiagnostics withQueries(List<MdnsQueryLogEntry> queries) => DebugDiagnostics(
          advertised: const [],
          backend: 'responder',
          hostLabel: 'bikecontrol-3f2a',
          holdsMulticastLock: false,
          discovered: const [],
          discoveryRan: false,
          addressReport: const AddressPickReport(chosen: null, candidates: []),
          servers: const [],
          permissions: const PermissionsSnapshot(localNetworkInferred: null),
          recentQueries: queries,
        );

    test('renders each query with its source, QU bit and how it was answered', () {
      final text = withQueries([
        MdnsQueryLogEntry(
          at: DateTime(2026, 7, 30, 9, 41, 12),
          source: '192.168.178.92',
          sourcePort: 5353,
          wantsUnicast: true,
          questions: const ['PTR _wahoo-fitness-tnp._tcp.local'],
          answeredUnicast: true,
          answeredMulticast: true,
        ),
      ]).toText();

      expect(text, contains('mDNS queries received:'));
      expect(text, contains('192.168.178.92:5353'));
      expect(text, contains('QU'));
      expect(text, contains('PTR _wahoo-fitness-tnp._tcp.local'));
      expect(text, contains('unicast+multicast'));
    });

    test('marks a folded entry with its repeat count', () {
      final text = withQueries([
        MdnsQueryLogEntry(
          at: DateTime(2026, 7, 30, 20, 32, 33),
          source: '172.20.176.1',
          sourcePort: 5353,
          wantsUnicast: false,
          questions: const ['PTR _oculusal_sp._tcp.local'],
          answeredUnicast: false,
          answeredMulticast: false,
          count: 17,
        ),
      ]).toText();

      expect(text, contains('×17'));
      expect(text, contains('no answer'));
    });

    test('a single occurrence carries no count marker', () {
      final text = withQueries([
        MdnsQueryLogEntry(
          at: DateTime(2026, 7, 30, 20, 32, 38),
          source: '192.168.0.87',
          sourcePort: 5353,
          wantsUnicast: true,
          questions: const ['PTR _openbikecontrol._tcp.local'],
          answeredUnicast: true,
          answeredMulticast: false,
        ),
      ]).toText();

      expect(text, isNot(contains('×')));
    });

    test('says so when nothing has queried us', () {
      // The decisive line for "the trainer app on this machine cannot see
      // BikeControl": if no query ever arrived, the problem is upstream of our
      // responder, not in how we answer.
      expect(withQueries(const []).toText(), contains('(none)'));
    });
  });
}
