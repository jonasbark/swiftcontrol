import 'dart:io';

import 'package:mdns_dart/mdns_dart.dart';

final mdnsEmulator = MdnsEmulator();

void main() {
  mdnsEmulator.init();
}

class MdnsEmulator {
  void init() async {
    print('Starting mDNS server...');

    // Get local IP
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

    if (localIP == null) {
      print('Could not find network interface');
      return;
    }

    // Create service
    final service = await MDNSService.create(
      instance: 'KICKR BIKE SHIFT B84D',
      service: '_wahoo-fitness-tnp._tcp',
      port: 36867,
      //hostName: 'KICKR BIKE SHIFT B84D.local',
      ips: [localIP],
      txt: [
        'ble-service-uuids=FC82',
        'mac-address=68-67-25-6C-66-9C',
        'serial-number=234700181',
      ],
    );

    print('Service: ${service.instance} at ${localIP.address}:${service.port}');

    // Start server
    final server = MDNSServer(MDNSServerConfig(zone: service, reusePort: true));

    try {
      await server.start();
      print('Server started - advertising service!');

      await Future.delayed(Duration(seconds: 130));
    } finally {
      await server.stop();
      print('Server stopped');
    }
  }
}
