//INFO: This is a stub - contact me if you need the full implementation.
//
// The full implementation scores every interface (deprioritising VPN tunnels,
// virtualization bridges and link-local adapters) to pick the LAN address a
// trainer app can actually reach. This stub returns the first non-loopback
// IPv4 so the app compiles and still advertises a usable address.

import 'dart:io';

/// How the host's network interfaces are enumerated. Injectable so tests can
/// simulate multi-homed machines without touching the real network stack.
typedef InterfaceLister = Future<List<NetworkInterface>> Function();

/// One scored IPv4 candidate considered by [AdvertisedAddressPicker].
class AddressCandidate {
  final String interfaceName;
  final String address;
  final int score;
  final bool isVirtual;

  const AddressCandidate({
    required this.interfaceName,
    required this.address,
    required this.score,
    required this.isVirtual,
  });
}

/// The picker's decision plus the candidates it weighed — for diagnostics.
class AddressPickReport {
  final InternetAddress? chosen;
  final List<AddressCandidate> candidates;

  const AddressPickReport({required this.chosen, required this.candidates});
}

/// Picks the IPv4 address BikeControl advertises over mDNS.
class AdvertisedAddressPicker {
  AdvertisedAddressPicker._();

  /// Test seam: replace to simulate interface layouts; reset in tearDown.
  static InterfaceLister listInterfaces = _defaultLister;

  static Future<List<NetworkInterface>> _defaultLister() => NetworkInterface.list();

  /// The address to advertise plus every candidate considered.
  static Future<AddressPickReport> report() async {
    final interfaces = await listInterfaces();
    InternetAddress? best;
    final candidates = <AddressCandidate>[];
    for (final interface in interfaces) {
      for (final address in interface.addresses) {
        if (address.type != InternetAddressType.IPv4 || address.isLoopback) continue;
        candidates.add(AddressCandidate(
          interfaceName: interface.name,
          address: address.address,
          score: 0,
          isVirtual: false,
        ));
        best ??= address;
      }
    }
    return AddressPickReport(chosen: best, candidates: candidates);
  }

  /// The address to advertise, or null when the host has no usable IPv4.
  static Future<InternetAddress?> pick() async => (await report()).chosen;
}
