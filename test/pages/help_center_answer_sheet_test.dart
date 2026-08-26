// The reusable "help answer" bottom sheet (help_answer_sheet.dart) that Your
// Setup's three content-round explainer rows all open instead of growing
// three bespoke sheets — see help_center_your_setup_test.dart for the
// per-row integration coverage. This file pins the sheet's own generic
// contract in isolation: title/body render, a link action launches its URL
// and leaves the sheet open, a navigate action closes the sheet first and
// then fires its callback, and the Close row dismisses it.
import 'package:bike_control/gen/l10n.dart';
import 'package:bike_control/pages/help_center/widgets/help_answer_sheet.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:url_launcher_platform_interface/link.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

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

const _triggerKey = ValueKey('open-sheet-trigger');

Future<void> _pump(WidgetTester tester, {required List<HelpAnswerAction> actions}) async {
  await tester.pumpWidget(
    ShadcnApp(
      debugShowCheckedModeBanner: false,
      localizationsDelegates: const [AppLocalizations.delegate],
      supportedLocales: AppLocalizations.delegate.supportedLocales,
      home: Scaffold(
        child: Builder(
          builder: (context) => Button.primary(
            key: _triggerKey,
            onPressed: () => openHelpAnswerSheet(
              context,
              icon: Icons.info_outline,
              title: 'Sheet title',
              body: 'Sheet body text',
              actions: actions,
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.byKey(_triggerKey));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('renders the title and body', (tester) async {
    await _pump(tester, actions: const []);

    expect(find.text('Sheet title'), findsOneWidget);
    expect(find.text('Sheet body text'), findsOneWidget);
  });

  testWidgets('renders no action rows and just a close button when none are supplied', (tester) async {
    await _pump(tester, actions: const []);

    expect(find.byKey(const ValueKey('help-answer-action-anything')), findsNothing);
    expect(find.byKey(const ValueKey('help-answer-close')), findsOneWidget);
  });

  testWidgets('a link action launches its URL and leaves the sheet open', (tester) async {
    final fakeLauncher = _FakeUrlLauncher();
    UrlLauncherPlatform.instance = fakeLauncher;

    await _pump(
      tester,
      actions: const [
        HelpAnswerAction.link(id: 'docs', label: 'Read the docs', icon: Icons.link, url: 'https://example.com/docs'),
      ],
    );

    await tester.ensureVisible(find.byKey(const ValueKey('help-answer-action-docs')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('help-answer-action-docs')));
    await tester.pump();

    expect(fakeLauncher.launchedUrls, contains('https://example.com/docs'));
    expect(find.byType(HelpAnswerSheet), findsOneWidget, reason: 'a link action must not close the sheet');
  });

  testWidgets('a navigate action closes the sheet first, then fires its callback', (tester) async {
    var navigated = false;

    await _pump(
      tester,
      actions: [
        HelpAnswerAction.navigate(
          id: 'go',
          label: 'Go somewhere',
          icon: Icons.arrow_forward,
          onPressed: () => navigated = true,
        ),
      ],
    );

    await tester.ensureVisible(find.byKey(const ValueKey('help-answer-action-go')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('help-answer-action-go')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(navigated, isTrue);
    expect(find.byType(HelpAnswerSheet), findsNothing, reason: 'a navigate action must close the sheet first');
  });

  testWidgets('the close row dismisses the sheet', (tester) async {
    await _pump(tester, actions: const []);
    expect(find.byType(HelpAnswerSheet), findsOneWidget);

    await tester.ensureVisible(find.byKey(const ValueKey('help-answer-close')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('help-answer-close')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(HelpAnswerSheet), findsNothing);
  });
}
