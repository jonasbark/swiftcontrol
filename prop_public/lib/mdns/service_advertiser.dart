//INFO: This is a stub - contact me if you need the full implementation.
//
// The full implementation provides two backends — the OS responder (via the
// `nsd` plugin) and an in-process mDNS responder with pinned multicast egress.
// This stub keeps the public surface so the app compiles.

import 'dart:io';
import 'dart:typed_data';

class AdvertisedService {
  /// Instance name, e.g. 'BikeControl'.
  final String name;

  /// Service type without domain, e.g. '_wahoo-fitness-tnp._tcp'.
  final String type;

  final int port;

  /// The IPv4 address to advertise.
  final InternetAddress address;

  final Map<String, Uint8List> txt;

  AdvertisedService({
    required this.name,
    required this.type,
    required this.port,
    required this.address,
    required this.txt,
  });
}

abstract class ServiceAdvertisement {
  Future<void> unregister();
}

abstract class ServiceAdvertiser {
  /// Process-wide advertiser the emulators use.
  static ServiceAdvertiser instance = _StubServiceAdvertiser();

  /// The right backend for the current platform.
  static ServiceAdvertiser platformDefault() => _StubServiceAdvertiser();

  Future<ServiceAdvertisement> register(AdvertisedService service);
}

class _StubServiceAdvertiser implements ServiceAdvertiser {
  @override
  Future<ServiceAdvertisement> register(AdvertisedService service) => throw UnimplementedError();
}

/// The in-process mDNS responder backend (desktop + Android). Stubbed here.
class ResponderServiceAdvertiser implements ServiceAdvertiser {
  /// The dedicated mDNS hostname label (without `.local`) all services share.
  String get hostLabel => '';

  /// Android only: whether the active responder socket holds the multicast
  /// lock. False when nothing is currently advertised.
  bool get holdsMulticastLock => false;

  @override
  Future<ServiceAdvertisement> register(AdvertisedService service) => throw UnimplementedError();
}
