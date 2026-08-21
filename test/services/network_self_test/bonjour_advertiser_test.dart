import 'dart:io';
import 'dart:typed_data';

import 'package:bike_control/services/bonjour/bonjour_api.dart';
import 'package:bike_control/services/bonjour/bonjour_service_advertiser.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prop/mdns/service_advertiser.dart';
import 'package:prop/utils/advertised_service_registry.dart';

/// Records register()/deallocate() calls instead of touching dnssd.dll, so
/// [BonjourServiceAdvertiser] is testable off-Windows.
class FakeBonjourApi implements BonjourApi {
  @override
  bool isAvailable = true;

  int registerCallCount = 0;
  int deallocateCallCount = 0;
  final Object handle = Object();
  BonjourException? failWith;

  String? lastName;
  String? lastType;
  int? lastPort;
  Uint8List? lastTxtRecord;
  Object? lastDeallocatedHandle;

  @override
  Object register({required String name, required String type, required int port, required Uint8List txtRecord}) {
    registerCallCount++;
    lastName = name;
    lastType = type;
    lastPort = port;
    lastTxtRecord = txtRecord;
    final failure = failWith;
    if (failure != null) throw failure;
    return handle;
  }

  @override
  void deallocate(Object handle) {
    deallocateCallCount++;
    lastDeallocatedHandle = handle;
  }
}

AdvertisedService _service({String name = 'BikeControl', int port = 36867}) => AdvertisedService(
  name: name,
  type: '_openbikecontrol._tcp',
  port: port,
  address: InternetAddress('192.168.1.50'),
  txt: {'id': Uint8List.fromList('1337'.codeUnits)},
);

void main() {
  group('encodeTxtRecord', () {
    test('encodes a single key/value pair with a length-prefixed segment', () {
      final result = encodeTxtRecord({'id': Uint8List.fromList('1337'.codeUnits)});

      expect(result, Uint8List.fromList([7, ...'id='.codeUnits, ...'1337'.codeUnits]));
    });

    test('concatenates multiple keys in map iteration order', () {
      final result = encodeTxtRecord({
        'a': Uint8List.fromList([1]),
        'bb': Uint8List.fromList([2, 3]),
      });

      expect(
        result,
        Uint8List.fromList([
          3, ...'a='.codeUnits, 1, // 'a=' (2 bytes) + 1 value byte = 3
          5, ...'bb='.codeUnits, 2, 3, // 'bb=' (3 bytes) + 2 value bytes = 5
        ]),
      );
    });

    test('empty map yields an empty record', () {
      expect(encodeTxtRecord({}), isEmpty);
    });

    test('keeps value bytes verbatim, including non-ASCII bytes', () {
      final result = encodeTxtRecord({
        'v': Uint8List.fromList([0x00, 0xff, 0x7f]),
      });

      expect(result.sublist(result.length - 3), [0x00, 0xff, 0x7f]);
    });

    test('a 255-byte segment is accepted', () {
      // 'k=' is 2 bytes; a 253-byte value makes the segment exactly 255.
      expect(() => encodeTxtRecord({'k': Uint8List(253)}), returnsNormally);
    });

    test('throws ArgumentError when a key=value segment exceeds 255 bytes', () {
      // 'k=' is 2 bytes; a 254-byte value makes the segment 256, over the limit.
      expect(() => encodeTxtRecord({'k': Uint8List(254)}), throwsArgumentError);
    });
  });

  group('toNetworkByteOrder', () {
    test('swaps the two bytes of a 16-bit port', () {
      expect(toNetworkByteOrder(0x1234), 0x3412);
    });

    test('is its own inverse', () {
      for (final port in [0, 1, 36866, 36867, 8080, 65535]) {
        expect(toNetworkByteOrder(toNetworkByteOrder(port)), port);
      }
    });
  });

  group('RealBonjourApi', () {
    test('isAvailable is false on this (non-Windows) test host', () {
      expect(RealBonjourApi().isAvailable, isFalse);
    });
  });

  group('BonjourServiceAdvertiser', () {
    setUp(() => AdvertisedServiceRegistry.instance.clear());
    tearDown(() => AdvertisedServiceRegistry.instance.clear());

    test('register adds a registry record and passes the encoded TXT record to the api', () async {
      final api = FakeBonjourApi();
      final advertiser = BonjourServiceAdvertiser(api: api);

      final advertisement = await advertiser.register(_service());

      expect(api.registerCallCount, 1);
      expect(api.lastName, 'BikeControl');
      expect(api.lastType, '_openbikecontrol._tcp');
      expect(api.lastPort, 36867);
      expect(api.lastTxtRecord, encodeTxtRecord({'id': Uint8List.fromList('1337'.codeUnits)}));
      expect(AdvertisedServiceRegistry.instance.records, hasLength(1));

      await advertisement.unregister();

      expect(api.deallocateCallCount, 1);
      expect(api.lastDeallocatedHandle, api.handle);
      expect(AdvertisedServiceRegistry.instance.records, isEmpty);
    });

    test('unregister is idempotent: deallocate is called exactly once', () async {
      final api = FakeBonjourApi();
      final advertiser = BonjourServiceAdvertiser(api: api);
      final advertisement = await advertiser.register(_service());

      await advertisement.unregister();
      await advertisement.unregister();

      expect(api.deallocateCallCount, 1);
    });

    test('a BonjourException from the api propagates out of register() and leaves no registry record', () async {
      final api = FakeBonjourApi()..failWith = BonjourException('kDNSServiceErr_NameConflict (-65548)');
      final advertiser = BonjourServiceAdvertiser(api: api);

      await expectLater(() => advertiser.register(_service()), throwsA(isA<BonjourException>()));
      expect(AdvertisedServiceRegistry.instance.records, isEmpty);
    });

    test('isAvailable delegates to the api', () {
      final api = FakeBonjourApi()..isAvailable = false;
      final advertiser = BonjourServiceAdvertiser(api: api);

      expect(advertiser.isAvailable, isFalse);
    });
  });
}
