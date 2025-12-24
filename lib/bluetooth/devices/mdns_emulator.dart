import 'dart:io';

import 'package:bike_control/bluetooth/devices/trainer_connection.dart';
import 'package:bike_control/utils/keymap/buttons.dart';
import 'package:flutter/foundation.dart';
import 'package:nsd/nsd.dart';

/// Base class for mDNS-based emulators that advertise services over the network.
/// Provides common functionality for TCP server management, mDNS registration,
/// and network interface discovery.
abstract class MdnsEmulator extends TrainerConnection {
  ServerSocket? _tcpServer;
  Registration? _mdnsRegistration;
  Socket? _socket;

  MdnsEmulator({
    required super.title,
    required super.supportedActions,
  });

  /// Gets the TCP server instance, if available.
  @protected
  ServerSocket? get tcpServer => _tcpServer;

  /// Gets the current client socket connection, if available.
  @protected
  Socket? get socket => _socket;

  /// Sets the client socket connection.
  @protected
  set socket(Socket? value) => _socket = value;

  /// Gets the mDNS registration, if available.
  @protected
  Registration? get mdnsRegistration => _mdnsRegistration;

  /// Finds and returns a local IPv4 address from available network interfaces.
  /// Returns null if no suitable address is found.
  @protected
  Future<InternetAddress?> findLocalIP() async {
    final interfaces = await NetworkInterface.list();
    InternetAddress? localIP;

    for (final interface in interfaces) {
      for (final addr in interface.addresses) {
        if (addr.type == InternetAddressType.IPv4 && !addr.isLoopback) {
          localIP = addr;
          break;
        }
      }
      if (localIP != null) break;
    }

    return localIP;
  }

  /// Creates a TCP server on the specified port.
  /// The server listens on all IPv6 addresses (with v6Only: false to also accept IPv4).
  @protected
  Future<ServerSocket> createTcpServer(int port) async {
    try {
      _tcpServer = await ServerSocket.bind(
        InternetAddress.anyIPv6,
        port,
        shared: true,
        v6Only: false,
      );
      if (kDebugMode) {
        print('TCP Server started on port ${_tcpServer!.port}');
      }
      return _tcpServer!;
    } catch (e) {
      if (kDebugMode) {
        print('Failed to start server: $e');
      }
      rethrow;
    }
  }

  /// Registers an mDNS service with the given configuration.
  @protected
  Future<Registration> registerMdnsService(Service service) async {
    if (kDebugMode) {
      enableLogging(LogTopic.calls);
      enableLogging(LogTopic.errors);
    }
    disableServiceTypeValidation(true);

    _mdnsRegistration = await register(service);
    if (kDebugMode) {
      print('mDNS service registered: ${service.name}');
    }
    return _mdnsRegistration!;
  }

  /// Unregisters the mDNS service if one is registered.
  @protected
  void unregisterMdnsService() {
    if (_mdnsRegistration != null) {
      unregister(_mdnsRegistration!);
      _mdnsRegistration = null;
    }
  }

  /// Closes the TCP server and client socket.
  @protected
  void closeTcpServer() {
    _socket?.destroy();
    _socket = null;
    _tcpServer?.close();
    _tcpServer = null;
  }

  /// Writes data to the client socket.
  @protected
  void writeToSocket(Socket socket, List<int> data) {
    if (kDebugMode) {
      print('Sending response: ${bytesToHex(data)}');
    }
    socket.add(data);
  }

  /// Stops the emulator by closing connections and unregistering services.
  void stop() {
    isStarted.value = false;
    isConnected.value = false;
    closeTcpServer();
    unregisterMdnsService();
    if (kDebugMode) {
      print('Stopped ${runtimeType}');
    }
  }
}

/// Converts a list of bytes to a hexadecimal string representation.
String bytesToHex(List<int> bytes, {bool spaced = false}) {
  return bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join(spaced ? ' ' : '');
}

/// Converts a list of bytes to a readable hexadecimal string with spaces.
String bytesToReadableHex(List<int> bytes) {
  return bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join(' ');
}

/// Converts a hexadecimal string to a list of bytes.
List<int> hexToBytes(String hex) {
  final bytes = <int>[];
  for (var i = 0; i < hex.length; i += 2) {
    final byte = hex.substring(i, i + 2);
    bytes.add(int.parse(byte, radix: 16));
  }
  return bytes;
}
