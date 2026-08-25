// Coverage for `FeedbackPromptTrigger` — the once-per-launch bridge between
// `FeedbackPromptService.shouldShowPrompt` and the flow's `onShow` callback.
// `service.start()` runs higher in the widget tree than the page that owns a
// trigger, so `shouldShowPrompt` can already be `true` before a trigger
// attaches (e.g. this launch's trainer connection was counted between
// `service.start()` and the trigger being constructed) — a bare
// `addListener` would never fire for that case since the value doesn't
// change again. These tests pin `checkInitial()` covering that gap, the
// normal flip-to-true path, and the once-per-launch guard.
//
// Bug 5a (usage-fixes round): `review_session_count` persists across
// launches and pre-dates this feature, so an existing user could already be
// over the threshold at cold start with nothing counted yet *this* launch —
// `FeedbackPromptService` now additionally requires `_countedThisLaunch`
// before `shouldShowPrompt` can go true, so that stale-count-alone case must
// NOT fire (see the "does not fire" test below, and
// feedback_prompt_service_test.dart for the service-level coverage).
import 'package:bike_control/services/feedback_prompt_service.dart';
import 'package:bike_control/utils/settings/settings.dart';
import 'package:bike_control/widgets/feedback_prompt/feedback_prompt_flow.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<Settings> _settings() async {
  SharedPreferences.setMockInitialValues({});
  final settings = Settings();
  settings.prefs = await SharedPreferences.getInstance();
  return settings;
}

void main() {
  setUp(() {
    FeedbackPromptFlow.resetShownThisLaunchForTesting();
  });

  tearDown(() {
    FeedbackPromptFlow.resetShownThisLaunchForTesting();
  });

  test('checkInitial fires when this launch already counted a connection before the trigger attaches', () async {
    final settings = await _settings();
    await settings.setReviewSessionCount(FeedbackPromptService.sessionThreshold - 1);
    final trainer = ValueNotifier(false);
    final service = FeedbackPromptService(settings: settings, trainerConnections: [trainer]);
    service.start();

    // A connection gets counted (and shouldShowPrompt flips true) before any
    // trigger exists yet — e.g. the connection completes between
    // `service.start()` (run early, in main.dart) and the page that owns a
    // trigger even building.
    trainer.value = true;
    await Future.value();
    expect(
      service.shouldShowPrompt.value,
      isTrue,
      reason: 'precondition: already eligible before the trigger attaches',
    );

    var shown = 0;
    final trigger = FeedbackPromptTrigger(service: service, onShow: () => shown++);

    expect(shown, 0, reason: 'attaching alone must not fire — only checkInitial() or a later flip does');

    trigger.checkInitial();

    expect(shown, 1);

    trigger.dispose();
    service.dispose();
  });

  test('checkInitial does NOT fire just because a past launch already crossed the threshold (Bug 5a)', () async {
    final settings = await _settings();
    // Simulates an existing user: review_session_count persisted from
    // previous launches (the old review banner used the same key) is
    // already at/over threshold, but this launch's own trainer connection
    // has not been counted — the exact cold-start scenario Bug 5a reported.
    await settings.setReviewSessionCount(FeedbackPromptService.sessionThreshold);
    final service = FeedbackPromptService(settings: settings, trainerConnections: [ValueNotifier(false)]);
    service.start();
    expect(
      service.shouldShowPrompt.value,
      isFalse,
      reason: 'not eligible until this launch counts a connection of its own',
    );

    var shown = 0;
    final trigger = FeedbackPromptTrigger(service: service, onShow: () => shown++);
    trigger.checkInitial();

    expect(shown, 0, reason: 'must not fire at cold start purely from a stale persisted count');

    trigger.dispose();
    service.dispose();
  });

  test('fires on a later flip to true when not eligible at attach time', () async {
    final settings = await _settings();
    final trainer = ValueNotifier(false);
    final service = FeedbackPromptService(settings: settings, trainerConnections: [trainer]);
    service.start();
    expect(service.shouldShowPrompt.value, isFalse);

    var shown = 0;
    final trigger = FeedbackPromptTrigger(service: service, onShow: () => shown++);
    trigger.checkInitial();
    expect(shown, 0, reason: 'checkInitial is a no-op while ineligible');

    await settings.setReviewSessionCount(FeedbackPromptService.sessionThreshold - 1);
    trainer.value = true;
    await Future.value();

    expect(service.shouldShowPrompt.value, isTrue);
    expect(shown, 1);

    trigger.dispose();
    service.dispose();
  });

  test('never fires more than once per launch, across triggers and repeated flips', () async {
    final settings = await _settings();
    await settings.setReviewSessionCount(FeedbackPromptService.sessionThreshold - 1);
    final trainer = ValueNotifier(false);
    final service = FeedbackPromptService(settings: settings, trainerConnections: [trainer]);
    service.start();
    trainer.value = true;
    await Future.value();

    var shown = 0;
    final trigger = FeedbackPromptTrigger(service: service, onShow: () => shown++);
    trigger.checkInitial();
    trigger.checkInitial();
    expect(shown, 1);

    // Dismissing and coming back eligible later in the same launch must not
    // re-fire — nor should a second trigger instance attached afterwards.
    await service.dismiss();
    await settings.setReviewSessionCount(
      FeedbackPromptService.sessionThreshold + FeedbackPromptService.snoozeSessions - 1,
    );
    // Bug 5a: eligibility also requires this launch to count a connection —
    // a notifier already `true` at construction never fires a change event,
    // so construct false and flip it like a real connection would.
    final trainer2 = ValueNotifier(false);
    final service2 = FeedbackPromptService(settings: settings, trainerConnections: [trainer2]);
    service2.start();
    trainer2.value = true;
    await Future.value();
    expect(service2.shouldShowPrompt.value, isTrue);

    var shownAgain = 0;
    final trigger2 = FeedbackPromptTrigger(service: service2, onShow: () => shownAgain++);
    trigger2.checkInitial();

    expect(shownAgain, 0, reason: 'shownThisLaunch guards across the whole app launch, not per-trigger');
    expect(shown, 1);

    trigger.dispose();
    trigger2.dispose();
    service.dispose();
    service2.dispose();
  });

  test('dispose stops the trigger from reacting to further changes', () async {
    final settings = await _settings();
    final trainer = ValueNotifier(false);
    final service = FeedbackPromptService(settings: settings, trainerConnections: [trainer]);
    service.start();

    var shown = 0;
    final trigger = FeedbackPromptTrigger(service: service, onShow: () => shown++);
    trigger.dispose();

    await settings.setReviewSessionCount(FeedbackPromptService.sessionThreshold - 1);
    trainer.value = true;
    await Future.value();

    expect(service.shouldShowPrompt.value, isTrue);
    expect(shown, 0);

    service.dispose();
  });
}
