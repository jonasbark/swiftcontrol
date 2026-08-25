// Geometry regression coverage for the layout-fidelity rework against
// `docs/design-mockups/Help Center.dc.html` (see the widget-snapshot skill:
// these are the assertions kept after the visual check — not a golden test).
// Pins: the 36x36 icon tile, the focused card's brand-blue border (vs. an
// unfocused card's default border), and the three equal-width, same-row
// community buttons.
import 'package:bike_control/gen/l10n.dart';
import 'package:bike_control/pages/help_center/help_center_page.dart';
import 'package:bike_control/utils/actions/base_actions.dart';
import 'package:bike_control/utils/core.dart';
import 'package:bike_control/widgets/ui/colors.dart' show BKColor;
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Future<void> _pump(WidgetTester tester, {HelpCenterFocus? focus}) async {
  await tester.pumpWidget(
    ShadcnApp(
      debugShowCheckedModeBanner: false,
      localizationsDelegates: const [AppLocalizations.delegate],
      supportedLocales: AppLocalizations.delegate.supportedLocales,
      // Mirrors main.dart's real theme + the global CardTheme it applies
      // (1.5px border) — both materially affect this page's rendering.
      theme: ThemeData(
        colorScheme: ColorSchemes.lightSlate.copyWith(
          mutedForeground: () => const Color(0xFFA1A1AA),
          primary: () => BKColor.main,
        ),
        typography: Typography.geist(),
        radius: 0.7,
      ),
      home: ComponentTheme<CardTheme>(
        data: const CardTheme(borderWidth: 1.5),
        child: HelpCenterPage(focus: focus),
      ),
    ),
  );
}

/// The colour of the outermost bordered box a `Card` renders (see
/// shadcn_flutter's `OutlinedContainer`, which nests two `AnimatedContainer`s
/// — the border lives on the first one in a depth-first search).
Color? _cardBorderColor(WidgetTester tester, Finder cardFinder) {
  final container = tester.widget<AnimatedContainer>(
    find.descendant(of: cardFinder, matching: find.byType(AnimatedContainer)).first,
  );
  final decoration = container.decoration as BoxDecoration;
  return (decoration.border as Border?)?.top.color;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await initializeDateFormatting();
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'http://127.0.0.1:9',
      anonKey: 'help-center-layout-test-anon-key',
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

  testWidgets('Your Setup card border turns brand blue when focused; others keep the default border', (
    tester,
  ) async {
    await _pump(tester, focus: HelpCenterFocus.yourSetup);
    // Not pumpAndSettle: KnownIssuesSection fires a real, unmocked network
    // fetch on initState (see help_center_page_test.dart).
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    final yourSetupCard = find.descendant(
      of: find.byKey(const ValueKey('help-your-setup')),
      matching: find.byType(Card),
    );
    final knownIssuesCard = find.ancestor(of: find.text('Known issues'), matching: find.byType(Card));

    expect(_cardBorderColor(tester, yourSetupCard), BKColor.main, reason: 'focused card border turns brand blue');
    expect(
      _cardBorderColor(tester, knownIssuesCard),
      isNot(BKColor.main),
      reason: 'divergence 1: "everything else is unchanged" — other cards keep their default border colour',
    );

    expect(tester.takeException(), isNull);
  });

  testWidgets('section header icon tiles are 36x36', (tester) async {
    await _pump(tester);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    final iconTiles = find.byWidgetPredicate((w) => w is Container && w.decoration is BoxDecoration && w.child is Icon);
    expect(iconTiles, findsWidgets, reason: 'sanity: section header icon tiles are Containers wrapping an Icon');
    for (final tile in iconTiles.evaluate()) {
      expect(
        (tile.renderObject! as RenderBox).size,
        const Size(36, 36),
        reason: 'icon tile must be 36x36 per the mockup',
      );
    }

    expect(tester.takeException(), isNull);
  });

  testWidgets('Reddit/Facebook/GitHub render as three same-row community buttons, not a stacked list', (
    tester,
  ) async {
    await _pump(tester);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.scrollUntilVisible(find.text('GitHub'), 400, scrollable: find.byType(Scrollable).first);
    await tester.pump();

    final redditRect = tester.getRect(find.text('Reddit'));
    final facebookRect = tester.getRect(find.text('Facebook'));
    final githubRect = tester.getRect(find.text('GitHub'));

    expect(redditRect.top, facebookRect.top, reason: 'community buttons sit on the same row');
    expect(facebookRect.top, githubRect.top, reason: 'community buttons sit on the same row');
    expect(redditRect.left, lessThan(facebookRect.left), reason: 'Reddit, Facebook, GitHub, left to right');
    expect(facebookRect.left, lessThan(githubRect.left), reason: 'Reddit, Facebook, GitHub, left to right');

    expect(tester.takeException(), isNull);
  });
}
