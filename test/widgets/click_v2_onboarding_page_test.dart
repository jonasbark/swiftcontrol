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

  Future<void> swipeNext(WidgetTester tester) async {
    await tester.drag(find.byType(PageView), const Offset(-500, 0));
    await tester.pumpAndSettle();
  }

  // The two decision-page CTAs, checked as an actual tappable Button rather
  // than a blanket "no Button" assertion — the header close icon and the
  // "why is this needed?" / alternatives links are Buttons too, and would
  // make a type-only assertion vacuous.
  Finder decisionButton(String text) => find.widgetWithText(Button, text);

  testWidgets('page 0 shows the left-side option and the swipe hint, with no applying button', (tester) async {
    await pumpPage(tester);

    expect(find.text('Use the left side only'), findsOneWidget);
    expect(find.text('Drops out a minute after your last button press — reconnects on its own'), findsOneWidget);
    expect(find.text('Swipe to see the other option'), findsWidgets);
    expect(find.byType(ClickContours), findsOneWidget);

    expect(decisionButton('Use the left side'), findsNothing);
    expect(decisionButton('Unlock with Zwift'), findsNothing);
  });

  testWidgets('swiping once reveals the unlock-with-Zwift option, still with no applying button', (tester) async {
    await pumpPage(tester);
    await swipeNext(tester);

    expect(find.text('Unlock with Zwift'), findsWidgets);
    expect(find.text('Needs unlocking with the Zwift app every 24 hours'), findsOneWidget);
    expect(find.text('Swipe to see the other option'), findsWidgets);

    expect(decisionButton('Use the left side'), findsNothing);
    expect(decisionButton('Unlock with Zwift'), findsNothing);
  });

  testWidgets('swiping twice shows the decision page with both option buttons', (tester) async {
    await pumpPage(tester);
    await swipeNext(tester);
    await swipeNext(tester);

    expect(find.text('Which one do you want?'), findsOneWidget);
    expect(decisionButton('Use the left side'), findsOneWidget);
    expect(decisionButton('Unlock with Zwift'), findsOneWidget);
    expect(find.text('No Zwift needed · left controller only'), findsOneWidget);
    expect(find.text('Both controllers · unlock every 24 hours'), findsOneWidget);
  });

  testWidgets('tapping the left-side button on the decision page applies that mode', (tester) async {
    await pumpPage(tester);
    await swipeNext(tester);
    await swipeNext(tester);

    await tester.tap(decisionButton('Use the left side'));
    await tester.pumpAndSettle();

    expect(core.settings.getUnlockWithZwift(), isFalse);
    expect(core.settings.getClickV2OnboardingDone(), isTrue);
  });

  testWidgets('tapping the Zwift button on the decision page applies that mode', (tester) async {
    await pumpPage(tester);
    await swipeNext(tester);
    await swipeNext(tester);

    await tester.tap(decisionButton('Unlock with Zwift'));
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

  testWidgets('the dot indicator renders three dots', (tester) async {
    await pumpPage(tester);

    // Scoped to the dot row itself — shadcn's own widgets use AnimatedContainer
    // internally too, so a blanket byType(AnimatedContainer) would overcount.
    expect(
      find.descendant(of: find.byKey(const ValueKey('click-onboarding-dots')), matching: find.byType(AnimatedContainer)),
      findsNWidgets(3),
    );
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
