import 'package:flutter/foundation.dart';
import 'package:prop/mdns/service_advertiser.dart';

/// Records register() calls without any real sockets. Shared between the
/// backend-selection test (Task 3) and the fix-dispatcher test (Task 10) —
/// both need a [ServiceAdvertiser.instance] fake that proves registrations
/// happened without touching any plugin or real network.
class RecordingAdvertiser implements ServiceAdvertiser {
  final services = <AdvertisedService>[];

  @override
  ValueListenable<String?> get advertisedAddress => ServiceAdvertiser.untrackedAddress;

  @override
  Future<ServiceAdvertisement> register(AdvertisedService service) async {
    services.add(service);
    return RecordingRegistration(this, service);
  }
}

class RecordingRegistration implements ServiceAdvertisement {
  RecordingRegistration(this.owner, this.service);
  final RecordingAdvertiser owner;
  final AdvertisedService service;

  @override
  Future<void> unregister() async => owner.services.remove(service);
}
