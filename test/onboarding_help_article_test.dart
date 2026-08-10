// Regression: a Zwift Play on firmware 2.x (ZwiftPlayFw2 extends ZwiftRide)
// resolved to the Zwift Ride help article; ZwiftClickV2RightSide had the same
// hole. The per-combo article must name the hardware the rider actually owns.
import 'package:bike_control/bluetooth/devices/base_device.dart';
import 'package:bike_control/bluetooth/devices/zwift/zwift_clickv2_right_side.dart';
import 'package:bike_control/bluetooth/devices/zwift/zwift_play_fw2.dart';
import 'package:bike_control/bluetooth/devices/zwift/zwift_ride.dart';
import 'package:bike_control/gen/l10n.dart';
import 'package:bike_control/main.dart' show OtherLocalizationsDelegate;
import 'package:bike_control/utils/help_article.dart';
import 'package:bike_control/utils/keymap/apps/my_whoosh.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:universal_ble/universal_ble.dart';

import 'widget_snapshot.dart';

Future<void> main() async {
  await ensureSnapshotHarness();

  Future<BuildContext> pumpContext(WidgetTester tester) async {
    await tester.pumpWidget(
      ShadcnApp(
        debugShowCheckedModeBanner: false,
        localizationsDelegates: [
          ...ShadcnLocalizations.localizationsDelegates,
          const OtherLocalizationsDelegate(),
          AppLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.delegate.supportedLocales,
        theme: ThemeData(colorScheme: ColorSchemes.lightSlate, radius: 0.7),
        home: const SizedBox(),
      ),
    );
    await tester.pump();
    return tester.element(find.byType(SizedBox));
  }

  void check(BuildContext context, BaseDevice device, String expectedSlug) {
    final article = helpArticleFor(context, controller: device, app: MyWhoosh());
    expect(article, isNotNull);
    expect(article!.url, contains('use-$expectedSlug-with-mywhoosh'),
        reason: '${device.runtimeType} must resolve to the $expectedSlug article, got ${article.url}');
  }

  testWidgets('help articles name the actual hardware', (tester) async {
    final context = await pumpContext(tester);
    check(context, ZwiftPlayFw2(BleDevice(deviceId: 'p2', name: 'Zwift Play')), 'zwift-play');
    check(context, ZwiftClickV2RightSide(BleDevice(deviceId: 'r1', name: 'Click V2 R')), 'zwift-click-v2');
    check(context, ZwiftRide(BleDevice(deviceId: 'zr', name: 'Zwift Ride')), 'zwift-ride');
  });
}
