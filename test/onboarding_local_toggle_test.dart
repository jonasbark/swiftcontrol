// Regression: tapping the Local method tile on step 5 opened the permission
// sheet with a context above the wizard's Scaffold ("No DrawerOverlay found")
// because _body/_footer were built with the page-level context. This walks
// the real wizard to step 5 and taps Local.
import 'package:bike_control/gen/l10n.dart';
import 'package:bike_control/main.dart' show OtherLocalizationsDelegate;
import 'package:bike_control/pages/button_edit.dart' show SelectableCard;
import 'package:bike_control/pages/onboarding/onboarding_page.dart';
import 'package:bike_control/utils/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import 'widget_snapshot.dart';

Future<void> main() async {
  await ensureSnapshotHarness();

  testWidgets('Local tile on step 5 opens the permission sheet without crashing', (tester) async {
    tester.view.physicalSize = const Size(390, 800) * 3.0;
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    // Keep the controller step from kicking off a real BLE scan in the test
    // environment — performScanning early-returns while isScanning is set.
    core.connection.isScanning.value = true;
    addTearDown(() => core.connection.isScanning.value = false);

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
        home: const OnboardingPage(),
      ),
    );
    await tester.pump();

    Future<void> settle() async {
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
    }

    Future<void> tapContinue() async {
      await tester.tap(find.byType(PrimaryButton).last);
      await settle();
    }

    // Step 1: pick the first app, continue.
    await tester.tap(find.byType(SelectableCard).first);
    await settle();
    await tapContinue();

    // Step 2: pick "on this device", continue.
    await tester.tap(find.byType(SelectableCard).first);
    await settle();
    await tapContinue();

    // Step 3 (controller): footer's last GhostButton is "can't find" /
    // "set up later" depending on phase — press through to step 4.
    await tester.tap(find.byType(GhostButton).last);
    await settle();
    await tester.tap(find.byType(GhostButton).last);
    await settle();

    // Step 4 (virtual shifting): ghost footer skips it.
    await tester.tap(find.byType(GhostButton).last);
    await settle();

    // Step 5: tap the Local method tile (keyboard icon).
    expect(find.byIcon(LucideIcons.keyboard), findsOneWidget, reason: 'should be on step 5');
    await tester.tap(find.byIcon(LucideIcons.keyboard));
    await settle();
    await tester.pump(const Duration(milliseconds: 400));

    expect(tester.takeException(), isNull, reason: 'Local toggle must not crash (DrawerOverlay regression)');
  });
}
