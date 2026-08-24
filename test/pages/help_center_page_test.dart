// Task 8: Help Center page skeleton. The page hosts sections for two later
// tasks ("Your setup", "Known issues", "Pricing & account" — placeholders
// only, filled in by Tasks 9-11) alongside the sections this task ships in
// full (Guides & videos, Troubleshooting, Contact & community, lifted from
// the old help-button dropdown). These tests pin: every section header
// renders, the `focus: HelpCenterFocus.yourSetup` constructor scrolls the
// your-setup placeholder into view, and the help button now pushes this page
// instead of opening the old dropdown.
import 'package:bike_control/gen/l10n.dart';
import 'package:bike_control/pages/help_center/help_center_page.dart';
import 'package:bike_control/utils/actions/base_actions.dart';
import 'package:bike_control/utils/core.dart';
import 'package:bike_control/widgets/ui/help_button.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Future<void> _pump(WidgetTester tester, Widget child) {
  return tester.pumpWidget(
    ShadcnApp(
      debugShowCheckedModeBanner: false,
      localizationsDelegates: const [AppLocalizations.delegate],
      supportedLocales: AppLocalizations.delegate.supportedLocales,
      home: child,
    ),
  );
}

Future<void> main() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  final l10n = await AppLocalizations.load(const Locale('en'));

  // HelpButton's re-check-on-return fix touches `core.supabase`; give it an
  // offline dummy instance (no session, so no request is ever made) rather
  // than crashing on the un-initialized singleton.
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'http://127.0.0.1:9',
      anonKey: 'help-center-test-anon-key',
      debug: false,
      authOptions: const FlutterAuthClientOptions(
        localStorage: EmptyLocalStorage(),
        detectSessionInUri: false,
        autoRefreshToken: false,
      ),
    );
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    core.settings.prefs = await SharedPreferences.getInstance();
    core.actionHandler = StubActions();
  });

  testWidgets('renders every section header', (tester) async {
    await _pump(tester, const HelpCenterPage());
    await tester.pump();

    expect(find.text(l10n.helpCenterGuides), findsOneWidget);
    expect(find.text(l10n.troubleshootingPage), findsOneWidget);
    expect(find.text(l10n.helpCenterYourSetup), findsOneWidget);
    expect(find.text(l10n.helpCenterKnownIssues), findsOneWidget);
    expect(find.text(l10n.helpCenterPricingFaq), findsOneWidget);
    expect(find.text(l10n.helpCenterContact), findsOneWidget);
  });

  testWidgets('focus: yourSetup scrolls the your-setup placeholder into view', (tester) async {
    // Shrink the viewport so the your-setup section (several sections deep)
    // starts out of view — otherwise "scrolled into view" is a no-op.
    const viewportHeight = 350.0;
    tester.view.physicalSize = const Size(400, viewportHeight);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await _pump(tester, const HelpCenterPage());
    await tester.pump();
    final unfocusedRect = tester.getRect(find.byKey(const ValueKey('help-your-setup')));
    expect(
      unfocusedRect.top,
      greaterThan(viewportHeight),
      reason: 'sanity: section starts below the fold without focus',
    );

    // Force a full unmount before the next pump — reusing the same element
    // tree would reuse the State object too, and this page's focus handling
    // (like `revealOverlaySection` on the proxy details page) runs from
    // `initState`, mirroring how a freshly-pushed route always behaves.
    await tester.pumpWidget(const SizedBox());
    await _pump(tester, const HelpCenterPage(focus: HelpCenterFocus.yourSetup));
    await tester.pumpAndSettle();

    final focusedRect = tester.getRect(find.byKey(const ValueKey('help-your-setup')));
    expect(focusedRect.top, greaterThanOrEqualTo(0));
    expect(focusedRect.top, lessThan(viewportHeight), reason: 'ensureVisible scrolled the section onto screen');
  });

  testWidgets('help button push opens HelpCenterPage', (tester) async {
    await _pump(tester, const HelpButton(isMobile: false));
    await tester.pump();

    expect(find.byType(HelpCenterPage), findsNothing);

    await tester.tap(find.byType(HelpButton));
    await tester.pumpAndSettle();

    expect(find.byType(HelpCenterPage), findsOneWidget);
  });

  testWidgets('help button awaits the pushed HelpCenterPage and re-checks unread on return', (tester) async {
    // Regression: HelpButton stays mounted under the pushed route and its
    // own `_hasUnread` badge was never re-synced when the rider returned —
    // only ContactCommunitySection's local flag got reset. `onPressed` now
    // awaits `context.push` and re-runs `_checkForUnread` afterwards; this
    // pins that the round trip completes cleanly (no session in tests, so
    // `_checkForUnread` no-ops past its `currentSession == null` guard, but
    // the awaited continuation must still run without throwing).
    await _pump(tester, const HelpButton(isMobile: false));
    await tester.pump();

    await tester.tap(find.byType(HelpButton));
    await tester.pumpAndSettle();
    expect(find.byType(HelpCenterPage), findsOneWidget);

    await tester.tap(find.byType(IconButton).first);
    await tester.pumpAndSettle();

    expect(find.byType(HelpCenterPage), findsNothing);
    expect(find.byType(HelpButton), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
