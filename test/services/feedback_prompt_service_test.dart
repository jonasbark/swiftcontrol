import 'package:bike_control/services/feedback_prompt_service.dart';
import 'package:bike_control/utils/settings/settings.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late Settings settings;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    settings = Settings();
    settings.prefs = await SharedPreferences.getInstance();
  });

  group('FeedbackPromptService', () {
    test('does not show banner before threshold', () async {
      final trainer = ValueNotifier(false);
      final service = FeedbackPromptService(
        settings: settings,
        trainerConnections: [trainer],
      );
      service.start();

      trainer.value = true;
      await Future.value();

      expect(settings.getReviewSessionCount(), 1);
      expect(service.shouldShowPrompt.value, false);

      service.dispose();
    });

    test('counts at most once per app launch even if connection toggles', () async {
      final trainer = ValueNotifier(false);
      final service = FeedbackPromptService(
        settings: settings,
        trainerConnections: [trainer],
      );
      service.start();

      trainer.value = true;
      trainer.value = false;
      trainer.value = true;
      trainer.value = false;
      trainer.value = true;
      await Future.value();

      expect(settings.getReviewSessionCount(), 1);

      service.dispose();
    });

    test('shows banner once threshold reached on a fresh launch', () async {
      await settings.setReviewSessionCount(FeedbackPromptService.sessionThreshold - 1);

      final trainer = ValueNotifier(false);
      final service = FeedbackPromptService(
        settings: settings,
        trainerConnections: [trainer],
      );
      service.start();

      trainer.value = true;
      await Future.value();

      expect(settings.getReviewSessionCount(), FeedbackPromptService.sessionThreshold);
      expect(service.shouldShowPrompt.value, true);

      service.dispose();
    });

    test('desktop platforms are eligible (no platform gate)', () async {
      await settings.setReviewSessionCount(FeedbackPromptService.sessionThreshold - 1);
      final trainer = ValueNotifier(false);
      final service = FeedbackPromptService(settings: settings, trainerConnections: [trainer]);
      service.start();

      // Bug 5a: eligibility requires this launch to have counted a
      // connection — a bare pre-existing/never-changed notifier wouldn't do
      // that, so flip it like a real connection would.
      trainer.value = true;
      await Future.value();

      expect(service.shouldShowPrompt.value, true);
      service.dispose();
    });

    test('markCompleted hides banner forever', () async {
      await settings.setReviewSessionCount(FeedbackPromptService.sessionThreshold - 1);

      final trainer = ValueNotifier(false);
      final service = FeedbackPromptService(
        settings: settings,
        trainerConnections: [trainer],
      );
      service.start();
      trainer.value = true;
      await Future.value();
      expect(service.shouldShowPrompt.value, true);

      await service.markCompleted();

      expect(service.shouldShowPrompt.value, false);
      expect(settings.getReviewCompleted(), true);

      service.dispose();
      final next = FeedbackPromptService(
        settings: settings,
        trainerConnections: [ValueNotifier(true)],
      );
      next.start();
      await Future.value();
      expect(next.shouldShowPrompt.value, false);
      next.dispose();
    });

    test('dismiss snoozes for 10 sessions then re-shows', () async {
      await settings.setReviewSessionCount(FeedbackPromptService.sessionThreshold - 1);

      final trainer = ValueNotifier(false);
      final service = FeedbackPromptService(
        settings: settings,
        trainerConnections: [trainer],
      );
      service.start();
      trainer.value = true;
      await Future.value();
      expect(service.shouldShowPrompt.value, true);

      await service.dismiss();
      expect(service.shouldShowPrompt.value, false);
      expect(settings.getReviewDismissedAtSessionCount(), FeedbackPromptService.sessionThreshold);

      service.dispose();

      await settings.setReviewSessionCount(
        FeedbackPromptService.sessionThreshold + FeedbackPromptService.snoozeSessions - 1,
      );
      var snoozed = FeedbackPromptService(
        settings: settings,
        trainerConnections: [ValueNotifier(true)],
      );
      snoozed.start();
      await Future.value();
      expect(snoozed.shouldShowPrompt.value, false);
      snoozed.dispose();

      await settings.setReviewSessionCount(
        FeedbackPromptService.sessionThreshold + FeedbackPromptService.snoozeSessions,
      );
      final reshownTrainer = ValueNotifier(false);
      var reshown = FeedbackPromptService(
        settings: settings,
        trainerConnections: [reshownTrainer],
      );
      reshown.start();
      // Bug 5a: eligibility also requires this launch to have counted a
      // connection — a notifier that's already `true` at construction never
      // fires a change event, so flip it like a real connection would.
      reshownTrainer.value = true;
      await Future.value();
      expect(reshown.shouldShowPrompt.value, true);
      reshown.dispose();
    });

    test('does not show banner while user is on trial time', () async {
      await settings.setReviewSessionCount(10);

      final trainer = ValueNotifier(true);
      final service = FeedbackPromptService(
        settings: settings,
        trainerConnections: [trainer],
        isOnTrial: () => true,
      );
      service.start();
      await Future.value();

      expect(service.shouldShowPrompt.value, false);

      service.dispose();
    });

    test('shows banner once trial ends', () async {
      await settings.setReviewSessionCount(10);

      var onTrial = true;
      final trainer = ValueNotifier(false);
      final service = FeedbackPromptService(
        settings: settings,
        trainerConnections: [trainer],
        isOnTrial: () => onTrial,
      );
      service.start();
      expect(service.shouldShowPrompt.value, false);

      onTrial = false;
      trainer.value = true;
      await Future.value();

      expect(service.shouldShowPrompt.value, true);

      service.dispose();
    });

    test('no trainer connection in this launch leaves session count untouched', () async {
      await settings.setReviewSessionCount(2);

      final trainer = ValueNotifier(false);
      final service = FeedbackPromptService(
        settings: settings,
        trainerConnections: [trainer],
      );
      service.start();
      await Future.value();

      expect(settings.getReviewSessionCount(), 2);
      expect(service.shouldShowPrompt.value, false);

      service.dispose();
    });
  });
}
