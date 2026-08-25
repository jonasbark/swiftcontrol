// Task 3: gate step of the feedback prompt flow. `FeedbackPromptFlow` is
// pumped directly (not via `showFeedbackPromptFlow`), so it has no ambient
// dialog/drawer route to pop into — these tests pin the gate's contents
// (thumbs, not-now), the step transition on thumbs-down, and that the old
// star-rating language never leaks into the sentiment gate.
//
// Task 12 extends this file with the negative step: "Get help" marks
// feedback completed and pushes `HelpCenterPage` focused on "Your setup";
// "Tell me what's wrong" hands off into the composer in complaint mode.
import 'package:bike_control/gen/l10n.dart';
import 'package:bike_control/main.dart' show OtherLocalizationsDelegate;
import 'package:bike_control/pages/help_center/help_center_page.dart';
import 'package:bike_control/services/feedback_prompt_service.dart';
import 'package:bike_control/services/feedback_submission_service.dart';
import 'package:bike_control/utils/actions/base_actions.dart';
import 'package:bike_control/utils/core.dart';
import 'package:bike_control/utils/settings/settings.dart';
import 'package:bike_control/widgets/feedback_prompt/feedback_prompt_flow.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Bare subclass so the negative-step tests don't need a real Supabase
/// client — mirrors the fakes in feedback_composer_test.dart /
/// feedback_prompt_positive_test.dart.
class _FakeSubmissionService extends FeedbackSubmissionService {
  _FakeSubmissionService()
    : super(
        client: SupabaseClient(
          'https://example.test',
          'test-anon-key',
          authOptions: const AuthClientOptions(autoRefreshToken: false),
        ),
      );

  final List<({FeedbackSentiment sentiment, FeedbackKind kind, String body})> submitted = [];

  @override
  Future<void> submit({required FeedbackSentiment sentiment, required FeedbackKind kind, required String body}) async {
    submitted.add((sentiment: sentiment, kind: kind, body: body));
  }
}

Future<FeedbackPromptService> _service() async {
  SharedPreferences.setMockInitialValues({});
  final settings = Settings();
  settings.prefs = await SharedPreferences.getInstance();
  return FeedbackPromptService(settings: settings, trainerConnections: [ValueNotifier(false)]);
}

Future<void> _pump(
  WidgetTester tester,
  FeedbackPromptService service, {
  FeedbackFlowStep initialStep = FeedbackFlowStep.gate,
  FeedbackSubmissionService? submissionService,
}) {
  return tester.pumpWidget(
    ShadcnApp(
      debugShowCheckedModeBanner: false,
      localizationsDelegates: [
        ...ShadcnLocalizations.localizationsDelegates,
        const OtherLocalizationsDelegate(),
        AppLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.delegate.supportedLocales,
      home: Scaffold(
        child: FeedbackPromptFlow(
          service: service,
          initialStep: initialStep,
          submissionService: submissionService,
        ),
      ),
    ),
  );
}

Future<void> main() async {
  TestWidgetsFlutterBinding.ensureInitialized();

  // The get-help test pushes the real HelpCenterPage, whose "Guides &
  // videos" section needs date-format locale data and a Supabase client
  // (only ever read, never hit — no session, so no request goes out).
  setUpAll(() async {
    await initializeDateFormatting();
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'http://127.0.0.1:9',
      anonKey: 'feedback-flow-test-anon-key',
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

  testWidgets('gate shows thumbs and not-now, tapping down goes to negative step', (tester) async {
    final service = await _service();
    await _pump(tester, service);

    expect(find.byKey(const ValueKey('feedback-thumbs-up')), findsOneWidget);
    expect(find.byKey(const ValueKey('feedback-thumbs-down')), findsOneWidget);
    expect(find.byKey(const ValueKey('feedback-not-now')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('feedback-thumbs-down')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('feedback-step-negative')), findsOneWidget);
  });

  testWidgets('tapping thumbs up goes to positive step', (tester) async {
    final service = await _service();
    await _pump(tester, service);

    await tester.tap(find.byKey(const ValueKey('feedback-thumbs-up')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('feedback-step-positive')), findsOneWidget);
  });

  testWidgets('not-now dismisses and snoozes', (tester) async {
    final service = await _service();
    await _pump(tester, service);

    expect(service.settings.getReviewDismissedAtSessionCount(), isNull);

    await tester.tap(find.byKey(const ValueKey('feedback-not-now')));
    await tester.pumpAndSettle();

    expect(service.settings.getReviewDismissedAtSessionCount(), isNotNull);
  });

  testWidgets('gate never contains the word rate or a star icon', (tester) async {
    final service = await _service();
    await _pump(tester, service);

    expect(find.textContaining(RegExp('rate', caseSensitive: false)), findsNothing);
    expect(find.byIcon(Icons.star_rate), findsNothing);
  });

  testWidgets('negative step shows get-help and tell-whats-wrong, never mentions the store', (tester) async {
    final service = await _service();
    await _pump(tester, service, initialStep: FeedbackFlowStep.negative);

    expect(find.byKey(const ValueKey('feedback-get-help')), findsOneWidget);
    expect(find.byKey(const ValueKey('feedback-tell-whats-wrong')), findsOneWidget);
    expect(find.textContaining(RegExp('store', caseSensitive: false)), findsNothing);
  });

  testWidgets('get-help marks feedback completed and pushes Help Center focused on your setup', (tester) async {
    final service = await _service();
    await _pump(tester, service, initialStep: FeedbackFlowStep.negative);

    expect(service.settings.getReviewCompleted(), isFalse);

    await tester.tap(find.byKey(const ValueKey('feedback-get-help')));
    await tester.pumpAndSettle();

    expect(service.settings.getReviewCompleted(), isTrue);
    final helpCenterPage = tester.widget<HelpCenterPage>(find.byType(HelpCenterPage));
    expect(helpCenterPage.focus, HelpCenterFocus.yourSetup);
  });

  testWidgets('tell-whats-wrong reaches the composer in complaint mode', (tester) async {
    final service = await _service();
    final submissionService = _FakeSubmissionService();
    await _pump(tester, service, initialStep: FeedbackFlowStep.negative, submissionService: submissionService);

    await tester.tap(find.byKey(const ValueKey('feedback-tell-whats-wrong')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('feedback-step-composer')), findsOneWidget);

    await tester.enterText(find.byType(TextArea), 'the shifting is off');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('feedback-send')));
    await tester.pumpAndSettle();

    expect(submissionService.submitted, hasLength(1));
    expect(submissionService.submitted.single.sentiment, FeedbackSentiment.down);
    expect(submissionService.submitted.single.kind, FeedbackKind.complaint);
  });
}
