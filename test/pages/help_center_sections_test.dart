// Task 10: the "Known issues" and "Guides & blog" (blog half of "Guides &
// videos") section bodies. Pins: known-issues renders one ghost row per
// fetched issue and routes each tap by the `helpBlogSlug` convention
// (bikecontrol.app/blog/<slug> when set, else bikecontrol.app/issues/<id> —
// see support_open_issues_banner.dart / support_intake_form.dart for the
// same rule); an empty or failing fetch hides the section entirely (no dead
// card); blog renders the fetched posts' titles.
import 'package:bike_control/gen/l10n.dart';
import 'package:bike_control/pages/help_center/widgets/blog_section.dart';
import 'package:bike_control/pages/help_center/widgets/known_issues_section.dart';
import 'package:bike_control/services/blog_service.dart';
import 'package:bike_control/services/support_chat_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:url_launcher_platform_interface/link.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

/// Records every URL passed to `launchUrlString`/`launchUrl` instead of
/// hitting a real platform channel, so taps are assertable.
class _FakeUrlLauncher extends UrlLauncherPlatform {
  final List<String> launchedUrls = [];

  @override
  LinkDelegate? get linkDelegate => null;

  @override
  Future<bool> canLaunch(String url) async => true;

  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    launchedUrls.add(url);
    return true;
  }
}

Future<void> _pump(WidgetTester tester, Widget child) {
  return tester.pumpWidget(
    ShadcnApp(
      debugShowCheckedModeBanner: false,
      localizationsDelegates: const [AppLocalizations.delegate],
      supportedLocales: AppLocalizations.delegate.supportedLocales,
      home: Scaffold(child: child),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    // BlogPostsWidget formats each post's date with DateFormat.yMMMd(),
    // which needs locale data initialized — nothing else in the suite
    // exercises intl's date formatting yet.
    await initializeDateFormatting();
  });

  group('KnownIssuesSection', () {
    testWidgets('renders a row per fetched issue', (tester) async {
      final issues = [
        const SupportIssue(id: 'i1', title: 'MyWhoosh drops connection'),
        const SupportIssue(id: 'i2', title: 'Zwift Click V2 pairing fails'),
      ];

      await _pump(tester, KnownIssuesSection(fetchIssues: () async => issues));
      await tester.pump();

      expect(find.text('MyWhoosh drops connection'), findsOneWidget);
      expect(find.text('Zwift Click V2 pairing fails'), findsOneWidget);
    });

    testWidgets('tapping a row without a blog slug opens the generic issue URL', (tester) async {
      final fake = _FakeUrlLauncher();
      final previous = UrlLauncherPlatform.instance;
      UrlLauncherPlatform.instance = fake;
      addTearDown(() => UrlLauncherPlatform.instance = previous);
      final issues = [const SupportIssue(id: 'abc123', title: 'Some issue')];

      await _pump(tester, KnownIssuesSection(fetchIssues: () async => issues));
      await tester.pump();

      await tester.tap(find.text('Some issue'));
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(fake.launchedUrls, ['https://bikecontrol.app/issues/abc123']);
    });

    testWidgets('tapping a row with a blog slug opens the blog post instead', (tester) async {
      final fake = _FakeUrlLauncher();
      final previous = UrlLauncherPlatform.instance;
      UrlLauncherPlatform.instance = fake;
      addTearDown(() => UrlLauncherPlatform.instance = previous);
      final issues = [
        const SupportIssue(id: 'abc123', title: 'Documented issue', helpBlogSlug: 'documented-issue'),
      ];

      await _pump(tester, KnownIssuesSection(fetchIssues: () async => issues));
      await tester.pump();

      await tester.tap(find.text('Documented issue'));
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(fake.launchedUrls, ['https://bikecontrol.app/blog/documented-issue']);
    });

    testWidgets('hides the section when the fetch returns no issues', (tester) async {
      await _pump(tester, KnownIssuesSection(fetchIssues: () async => const []));
      await tester.pump();

      expect(find.byType(Button), findsNothing);
      expect(find.byType(KnownIssuesSection), findsOneWidget, reason: 'header stays; only the body hides');
    });

    testWidgets('hides the section (and records, not throws) when the fetch fails', (tester) async {
      await _pump(tester, KnownIssuesSection(fetchIssues: () async => throw Exception('network down')));
      await tester.pump();

      expect(find.byType(Button), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('BlogSection', () {
    testWidgets('renders the fetched posts', (tester) async {
      final posts = [
        BlogPost(date: DateTime(2026, 1, 1), title: 'BikeControl 6.4 released', slug: 'bikecontrol-6-4'),
        BlogPost(date: DateTime(2025, 12, 1), title: 'Setting up virtual shifting', slug: 'virtual-shifting'),
      ];

      await _pump(tester, BlogSection(postsFuture: Future.value(posts)));
      await tester.pump();

      expect(find.text('BikeControl 6.4 released'), findsOneWidget);
      expect(find.text('Setting up virtual shifting'), findsOneWidget);
    });
  });
}
