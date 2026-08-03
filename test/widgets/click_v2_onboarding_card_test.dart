import 'package:bike_control/gen/l10n.dart';
import 'package:bike_control/pages/click_v2_onboarding.dart';
import 'package:bike_control/utils/core.dart';
import 'package:bike_control/widgets/click_v2/onboarding_card.dart';
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

  Future<void> pumpCard(WidgetTester tester) async {
    // Tapping the CTA below navigates into ClickV2OnboardingPage, whose hero
    // badges loop for as long as it's visible (see ClickContours) — these
    // tests exercise the card and the navigation, not that loop, so
    // animations are disabled to keep pumpAndSettle deterministic instead of
    // waiting out a Ticker that never stops on its own.
    tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(disableAnimations: true);
    await tester.pumpWidget(
      const ShadcnApp(
        localizationsDelegates: [AppLocalizations.delegate],
        supportedLocales: [Locale('en')],
        home: Scaffold(child: ClickV2OnboardingCard()),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('shows the device name, the setup hint and the CTA', (tester) async {
    await pumpCard(tester);

    expect(find.text('Zwift Click V2'), findsOneWidget);
    expect(find.text('Found nearby · setup needed'), findsOneWidget);
    expect(find.text("Let's get your Zwift Click V2 set up"), findsOneWidget);
  });

  testWidgets('the header is faded but the CTA stays at full strength', (tester) async {
    await pumpCard(tester);

    final header = tester.widget<Opacity>(find.byKey(const ValueKey('click-onboarding-card-header')));
    expect(header.opacity, lessThan(0.6));
    // Self-contained guard against a vacuous pass: find.ancestor(of: ...)
    // returns empty whenever its `of` finder matches nothing, so without this
    // the findsNothing check below would also pass if the CTA text weren't
    // rendered at all.
    expect(find.text("Let's get your Zwift Click V2 set up"), findsOneWidget);
    expect(
      find.ancestor(
        of: find.text("Let's get your Zwift Click V2 set up"),
        matching: find.byKey(const ValueKey('click-onboarding-card-header')),
      ),
      findsNothing,
    );
  });

  testWidgets('tapping the CTA opens the onboarding flow', (tester) async {
    await pumpCard(tester);

    await tester.tap(find.text("Let's get your Zwift Click V2 set up"));
    await tester.pumpAndSettle();

    expect(find.byType(ClickV2OnboardingPage), findsOneWidget);
  });
}
