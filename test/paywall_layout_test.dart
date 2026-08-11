// Regression: the paywall and SelectableCard are rendered inside scrolling
// drawers, where the cross axis is unbounded. Stretching a Row against that
// (or passing the constraints through a Stack) hands children an infinite
// height and layout dies with "RenderBox was not laid out".
import 'package:bike_control/gen/l10n.dart';
import 'package:bike_control/main.dart' show OtherLocalizationsDelegate;
import 'package:bike_control/pages/button_edit.dart' show SelectableCard;
import 'package:bike_control/pages/paywall.dart';
import 'package:bike_control/utils/iap/iap_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import 'widget_snapshot.dart';

Future<void> main() async {
  await ensureSnapshotHarness();

  Future<void> pumpInScrollView(WidgetTester tester, Widget child) async {
    tester.view.physicalSize = const Size(390, 800) * 3.0;
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
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
        // An unbounded-height host, exactly like the drawer's scroll view.
        home: SingleChildScrollView(child: child),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('paywall lays out inside a scroll view', (tester) async {
    IAPManager.instance.isPurchased.value = false;
    addTearDown(() => IAPManager.instance.isPurchased.value = true);
    await pumpInScrollView(tester, const Paywall(defaultToFullVersion: false));
    expect(tester.takeException(), isNull);
  });

  testWidgets('SelectableCard lays out inside a scroll view', (tester) async {
    await pumpInScrollView(
      tester,
      Column(children: [
        SelectableCard(title: const Text('Option'), isActive: true, onPressed: () {}),
        SelectableCard(title: const Text('Other'), subtitle: const Text('sub'), isActive: false, onPressed: () {}),
      ]),
    );
    expect(tester.takeException(), isNull);
  });
}
