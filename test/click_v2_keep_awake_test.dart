import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:bike_control/bluetooth/connection.dart';
import 'package:bike_control/bluetooth/devices/zwift/constants.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:universal_ble/universal_ble.dart';

BleDevice _advert({int? zwiftTypeByte, int companyId = ZwiftConstants.ZWIFT_MANUFACTURER_ID}) => BleDevice(
  deviceId: 'puck',
  name: 'Zwift Click',
  manufacturerDataList: [
    if (zwiftTypeByte != null) ManufacturerData(companyId, Uint8List.fromList([zwiftTypeByte])),
  ],
);

void main() {
  group('left-puck identification', () {
    test('recognises a left puck from its advert', () {
      expect(Connection.isClickV2LeftSideAdvert(_advert(zwiftTypeByte: ZwiftConstants.CLICK_V2_LEFT_SIDE)), isTrue);
    });

    test('does not mistake the right puck for its sibling', () {
      // The whole point is "is the *other* one here", so confusing the two
      // would make a lone right puck believe it had company.
      expect(Connection.isClickV2LeftSideAdvert(_advert(zwiftTypeByte: ZwiftConstants.CLICK_V2_RIGHT_SIDE)), isFalse);
    });

    test('ignores other Zwift controllers', () {
      expect(Connection.isClickV2LeftSideAdvert(_advert(zwiftTypeByte: ZwiftConstants.BC1)), isFalse);
      expect(Connection.isClickV2LeftSideAdvert(_advert(zwiftTypeByte: ZwiftConstants.RIDE_LEFT_SIDE)), isFalse);
      expect(Connection.isClickV2LeftSideAdvert(_advert(zwiftTypeByte: ZwiftConstants.RC1_LEFT_SIDE)), isFalse);
    });

    test('ignores the same byte from another vendor', () {
      expect(
        Connection.isClickV2LeftSideAdvert(_advert(zwiftTypeByte: ZwiftConstants.CLICK_V2_LEFT_SIDE, companyId: 0x004C)),
        isFalse,
      );
    });

    test('survives adverts with no manufacturer data at all', () {
      expect(Connection.isClickV2LeftSideAdvert(_advert()), isFalse);
      expect(Connection.isClickV2LeftSideAdvert(BleDevice(deviceId: 'bare', name: null)), isFalse);
    });
  });

  group('keep-awake strings', () {
    const keys = [
      'clickV2_keepAwakeNeedsLeftSide',
      'chainStepClickV2KeepAwake',
      'chainStepClickV2KeepAwakeHint',
    ];
    const locales = ['en', 'de', 'fr', 'es', 'it', 'pl'];

    test('are translated in every shipped language', () {
      for (final locale in locales) {
        final arb = jsonDecode(File('lib/i10n/intl_$locale.arb').readAsStringSync()) as Map<String, dynamic>;
        for (final key in keys) {
          expect(arb.containsKey(key), isTrue, reason: '$locale is missing $key');
          expect(
            (arb[key] as String).trim(),
            isNotEmpty,
            reason: '$locale has an empty $key',
          );
        }
      }
    });

    test('are not left as untranslated copies of the English', () {
      // A placeholder that was never translated is worse than a missing key:
      // it passes the presence check and ships English to every rider.
      final en = jsonDecode(File('lib/i10n/intl_en.arb').readAsStringSync()) as Map<String, dynamic>;
      for (final locale in locales.where((l) => l != 'en')) {
        final arb = jsonDecode(File('lib/i10n/intl_$locale.arb').readAsStringSync()) as Map<String, dynamic>;
        for (final key in keys) {
          expect(arb[key], isNot(en[key]), reason: '$locale still carries the English $key');
        }
      }
    });
  });
}
