import 'package:bike_control/gen/l10n.dart';
import 'package:bike_control/pages/click_v2_onboarding.dart';
import 'package:bike_control/utils/actions/base_actions.dart';
import 'package:bike_control/utils/core.dart';
import 'package:bike_control/widgets/unlock_toggle.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    core.actionHandler = StubActions();
    core.settings.prefs = await SharedPreferences.getInstance();
    await AppLocalizations.load(const Locale('en'));
  });

  testWidgets('offers a way back into the onboarding explainer', (tester) async {
    // "Set up again" below navigates into ClickV2OnboardingPage, whose hero
    // badges loop for as long as it's visible (see ClickContours) — this
    // test exercises the navigation, not that loop, so animations are
    // disabled to keep pumpAndSettle deterministic instead of waiting out a
    // Ticker that never stops on its own.
    tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(disableAnimations: true);
    await tester.pumpWidget(
      ShadcnApp(
        localizationsDelegates: const [AppLocalizations.delegate],
        supportedLocales: const [Locale('en')],
        home: Scaffold(child: const UnlockToggle(children: [])),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Set up again'), findsOneWidget);

    await tester.tap(find.text('Set up again'));
    await tester.pumpAndSettle();

    expect(find.byType(ClickV2OnboardingPage), findsOneWidget);
  });

  // The explainer is the only place the unlock mode is chosen — a dropdown
  // beside it could set the setting without doing the work each mode needs.
  testWidgets('offers no unlock-mode picker of its own', (tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(disableAnimations: true);
    await tester.pumpWidget(
      ShadcnApp(
        localizationsDelegates: const [AppLocalizations.delegate],
        supportedLocales: const [Locale('en')],
        home: Scaffold(child: const UnlockToggle(children: [])),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(Select<bool>), findsNothing);
  });
}
