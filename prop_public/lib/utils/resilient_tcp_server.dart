//INFO: This is a stub - contact me if you need the full implementation.
//
// The full implementation is a single-client TCP server with dual-stack
// listening, reconnect-supersede and port-fallback logic. This stub keeps the
// public surface so the app compiles.

import 'dart:io';

class ResilientTcpServer {
  ResilientTcpServer({
    required this.preferredPort,
    this.portAttempts = 5,
    this.forceIPv4 = false,
    this.label,
    required this.onClientConnected,
    required this.onData,
    required this.onClientDisconnected,
  }) : assert(portAttempts >= 1);

  final int preferredPort;
  final int portAttempts;
  final bool forceIPv4;
  final String? label;

  /// Every currently-running server, for the diagnostics block.
  static final List<ResilientTcpServer> activeServers = [];

  final void Function(Socket socket) onClientConnected;
  final void Function(Socket socket, List<int> data) onData;
  final void Function() onClientDisconnected;

  bool get isRunning => false;
  bool get hasClient => false;
  Socket? get client => null;
  int get boundPort => preferredPort;

  Future<void> start() async {}

  void dropClient() {}

  Future<void> stop() async {}
}
