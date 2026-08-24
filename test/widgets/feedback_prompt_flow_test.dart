// Task 3: gate step of the feedback prompt flow. `FeedbackPromptFlow` is
// pumped directly (not via `showFeedbackPromptFlow`), so it has no ambient
// dialog/drawer route to pop into — these tests pin the gate's contents
// (thumbs, not-now), the step transition on thumbs-down, and that the old
// star-rating language never leaks into the sentiment gate.
import 'package:bike_control/gen/l10n.dart';
import 'package:bike_control/main.dart' show OtherLocalizationsDelegate;
import 'package:bike_control/services/feedback_prompt_service.dart';
import 'package:bike_control/utils/settings/settings.dart';
import 'package:bike_control/widgets/feedback_prompt/feedback_prompt_flow.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
        child: FeedbackPromptFlow(service: service, initialStep: initialStep),
      ),
    ),
  );
}

void main() {
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
}
