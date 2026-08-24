// Coverage for `FeedbackPromptTrigger` — the once-per-launch bridge between
// `FeedbackPromptService.shouldShowPrompt` and the flow's `onShow` callback.
// `service.start()` runs higher in the widget tree than the page that owns a
// trigger, so `shouldShowPrompt` can already be `true` before a trigger
// attaches (e.g. the session threshold was crossed in a previous launch) — a
// bare `addListener` would never fire for that case since the value doesn't
// change again. These tests pin `checkInitial()` covering that gap, the
// normal flip-to-true path, and the once-per-launch guard.
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

  test('checkInitial fires when the service is already eligible at attach time', () async {
    final settings = await _settings();
    await settings.setReviewSessionCount(FeedbackPromptService.sessionThreshold);
    final service = FeedbackPromptService(settings: settings, trainerConnections: [ValueNotifier(false)]);
    service.start();
    expect(service.shouldShowPrompt.value, isTrue, reason: 'precondition: already eligible before the trigger attaches');

    var shown = 0;
    final trigger = FeedbackPromptTrigger(service: service, onShow: () => shown++);

    expect(shown, 0, reason: 'attaching alone must not fire — only checkInitial() or a later flip does');

    trigger.checkInitial();

    expect(shown, 1);

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
    await settings.setReviewSessionCount(FeedbackPromptService.sessionThreshold);
    final service = FeedbackPromptService(settings: settings, trainerConnections: [ValueNotifier(false)]);
    service.start();

    var shown = 0;
    final trigger = FeedbackPromptTrigger(service: service, onShow: () => shown++);
    trigger.checkInitial();
    trigger.checkInitial();
    expect(shown, 1);

    // Dismissing and coming back eligible later in the same launch must not
    // re-fire — nor should a second trigger instance attached afterwards.
    await service.dismiss();
    await settings.setReviewSessionCount(FeedbackPromptService.sessionThreshold + FeedbackPromptService.snoozeSessions);
    final trainer2 = ValueNotifier(true);
    final service2 = FeedbackPromptService(settings: settings, trainerConnections: [trainer2]);
    service2.start();
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
