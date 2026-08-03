import 'package:bike_control/gen/l10n.dart';
import 'package:bike_control/pages/click_v2_onboarding.dart';
import 'package:bike_control/utils/core.dart';
import 'package:bike_control/widgets/click_v2/click_contours.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    core.settings.prefs = await SharedPreferences.getInstance();
    await AppLocalizations.load(const Locale('en'));
  });

  // Harness matching test/widgets/emulation_card_test.dart — ShadcnApp with the
  // single English delegate is the pattern that works in this repo.
  Future<void> pumpPage(WidgetTester tester) async {
    // The hero's idle-timeout and lock badges loop for as long as the page is
    // visible (see ClickContours) — these tests exercise CTA/text/navigation
    // behaviour, not that loop, so animations are disabled here to keep
    // pumpAndSettle deterministic instead of waiting out a Ticker that never
    // stops on its own.
    tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(disableAnimations: true);
    await tester.pumpWidget(
      const ShadcnApp(
        localizationsDelegates: [AppLocalizations.delegate],
        supportedLocales: [Locale('en')],
        home: ClickV2OnboardingPage(),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('shows the first option, the hero and both fixed links', (tester) async {
    await pumpPage(tester);

    expect(find.text('Use the left side only'), findsOneWidget);
    expect(find.byType(ClickContours), findsOneWidget);
    expect(find.text('Why is this needed?'), findsOneWidget);
    expect(find.text('Rightfully annoyed by this? See controllers that just work'), findsOneWidget);
  });

  testWidgets('swiping reveals the unlock-with-Zwift option', (tester) async {
    await pumpPage(tester);

    await tester.drag(find.byType(PageView), const Offset(-500, 0));
    await tester.pumpAndSettle();

    expect(find.text('Unlock with Zwift'), findsWidgets);
    expect(find.text('Needs unlocking with the Zwift app every 24 hours'), findsOneWidget);
  });

  testWidgets('the left-side CTA applies that mode', (tester) async {
    await pumpPage(tester);

    await tester.tap(find.text('Use the left side'));
    await tester.pumpAndSettle();

    expect(core.settings.getUnlockWithZwift(), isFalse);
    expect(core.settings.getClickV2OnboardingDone(), isTrue);
  });

  testWidgets('the Zwift CTA applies that mode', (tester) async {
    await pumpPage(tester);

    await tester.drag(find.byType(PageView), const Offset(-500, 0));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Unlock with Zwift').last);
    await tester.pumpAndSettle();

    expect(core.settings.getUnlockWithZwift(), isTrue);
    expect(core.settings.getClickV2OnboardingDone(), isTrue);
  });

  testWidgets('closing without choosing writes nothing', (tester) async {
    await pumpPage(tester);

    await tester.tap(find.byKey(const ValueKey('click-onboarding-close')));
    await tester.pumpAndSettle();

    expect(core.settings.getClickV2OnboardingDone(), isFalse);
  });

  testWidgets('advantage and disadvantage rows settle into place', (tester) async {
    await pumpPage(tester);

    // The stagger is a one-shot entrance; once settled every row is opaque and
    // at its resting offset, so the page is never left half-faded.
    for (final text in [
      'No Zwift unlock — ever',
      'Works right away, no second app',
      'Drops out a minute after your last button press — reconnects on its own',
      'Only the left controller sends button presses',
    ]) {
      final opacity = tester.widget<FadeTransition>(
        find.ancestor(of: find.text(text), matching: find.byType(FadeTransition)).first,
      );
      expect(opacity.opacity.value, closeTo(1.0, 0.001), reason: 'row not fully faded in: $text');
    }
  });
}
