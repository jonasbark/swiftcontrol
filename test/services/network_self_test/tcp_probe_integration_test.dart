import 'package:bike_control/services/network_self_test/probes/active_probes.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prop/utils/resilient_tcp_server.dart';

/// [defaultTcpProbe] against a real [ResilientTcpServer]: proves the probe
/// self-connect is invisible to the server's normal client bookkeeping (no
/// `connected`/`disconnected` callbacks, `hasClient` stays false), and that a
/// server which has stopped listening makes the probe throw instead of
/// silently reporting success.
void main() {
  late List<String> events;
  late ResilientTcpServer server;

  setUp(() {
    events = [];
    server = ResilientTcpServer(
      preferredPort: 0,
      portAttempts: 1,
      label: 'OpenBikeControl',
      onClientConnected: (_) => events.add('connected'),
      onData: (socket, data) => events.add('data'),
      onClientDisconnected: () => events.add('disconnected'),
    );
  });

  tearDown(() async {
    await server.stop();
  });

  test('a self-connect succeeds without disturbing the server', () async {
    await server.start();
    // Guard: activeServers must contain the started instance, or
    // defaultTcpProbe's lookup by label would never find it.
    expect(ResilientTcpServer.activeServers, contains(server));

    await defaultTcpProbe('127.0.0.1', server.boundPort);

    expect(server.hasClient, isFalse);
    expect(events, isEmpty, reason: 'no connected/disconnected callbacks for a probe');
  });

  test('a probe throws once the server has stopped listening', () async {
    await server.start();
    final port = server.boundPort;
    await server.stop();

    expect(() => defaultTcpProbe('127.0.0.1', port), throwsA(anything));
  });
}
