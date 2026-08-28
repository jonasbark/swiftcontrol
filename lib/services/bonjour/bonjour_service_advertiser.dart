/// [ServiceAdvertiser] backend that hands the OBC registration to Apple
/// Bonjour's own daemon via dnssd.dll (Windows only).
///
/// Spec §12: on Windows the OS-responder backend must be Apple Bonjour, so
/// the record is owned by the very daemon MyWhoosh's `getaddrinfo`
/// (mdnsNSP) asks. See [BonjourApi] for why a registration held by our own
/// in-process responder or by the OS's native `nsd` responder does not
/// satisfy this.
library;

import 'package:bike_control/services/bonjour/bonjour_api.dart';
import 'package:flutter/foundation.dart';
import 'package:prop/mdns/service_advertiser.dart';
import 'package:prop/utils/advertised_service_registry.dart';

class BonjourServiceAdvertiser implements ServiceAdvertiser {
  final BonjourApi _api;

  BonjourServiceAdvertiser({BonjourApi? api}) : _api = api ?? RealBonjourApi();

  /// Whether dnssd.dll could be loaded on this machine.
  bool get isAvailable => _api.isAvailable;

  /// Bonjour's daemon publishes and maintains the host records for this
  /// registration, including following the machine to a new address, so there
  /// is nothing here for us to track.
  @override
  ValueListenable<String?> get advertisedAddress => ServiceAdvertiser.untrackedAddress;

  @override
  Future<ServiceAdvertisement> register(AdvertisedService service) async {
    final handle = _api.register(
      name: service.name,
      type: service.type,
      port: service.port,
      txtRecord: encodeTxtRecord(service.txt),
    );
    // A BonjourException from api.register above propagates out of this
    // method before a registry record is ever created.
    final record = AdvertisedServiceRegistry.instance.add(
      name: service.name,
      type: service.type,
      port: service.port,
      // Bonjour publishes its own hostname/address records for this
      // registration; the address is recorded here for diagnostics only
      // (Logs page / debugText), it is never sent to dnssd.dll.
      address: service.address.address,
      txt: service.txt,
    );
    return _BonjourAdvertisement(_api, handle, record);
  }
}

class _BonjourAdvertisement implements ServiceAdvertisement {
  final BonjourApi _api;
  final Object _handle;
  final AdvertisedRecord _record;
  bool _unregistered = false;

  _BonjourAdvertisement(this._api, this._handle, this._record);

  @override
  Future<void> unregister() async {
    if (_unregistered) return;
    _unregistered = true;
    AdvertisedServiceRegistry.instance.remove(_record);
    _api.deallocate(_handle);
  }
}
