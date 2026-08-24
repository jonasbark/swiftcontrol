import 'package:bike_control/utils/settings/settings.dart';
import 'package:flutter/foundation.dart';

class FeedbackPromptService {
  static const int sessionThreshold = 6;
  static const int snoozeSessions = 10;

  final Settings settings;
  final List<ValueListenable<bool>> trainerConnections;
  final bool Function() isOnTrial;

  final ValueNotifier<bool> shouldShowPrompt = ValueNotifier(false);

  bool _countedThisLaunch = false;
  final List<VoidCallback> _disposers = [];

  FeedbackPromptService({
    required this.settings,
    required this.trainerConnections,
    this.isOnTrial = _alwaysFalse,
  });

  static bool _alwaysFalse() => false;

  void start() {
    for (final notifier in trainerConnections) {
      void listener() => _onConnectionChanged(notifier);
      notifier.addListener(listener);
      _disposers.add(() => notifier.removeListener(listener));
    }
    _refreshBannerState();
  }

  void _onConnectionChanged(ValueListenable<bool> notifier) {
    if (_countedThisLaunch) return;
    if (notifier.value != true) return;
    _countedThisLaunch = true;
    final next = settings.getReviewSessionCount() + 1;
    settings.setReviewSessionCount(next).then((_) => _refreshBannerState());
  }

  void _refreshBannerState() {
    shouldShowPrompt.value = _isEligible();
  }

  bool _isEligible() {
    if (isOnTrial()) return false;
    if (settings.getReviewCompleted()) return false;
    final count = settings.getReviewSessionCount();
    if (count < sessionThreshold) return false;
    final dismissedAt = settings.getReviewDismissedAtSessionCount();
    if (dismissedAt != null && count - dismissedAt < snoozeSessions) {
      return false;
    }
    return true;
  }

  Future<void> markCompleted() async {
    await settings.setReviewCompleted(true);
    _refreshBannerState();
  }

  Future<void> dismiss() async {
    await settings.setReviewDismissedAtSessionCount(settings.getReviewSessionCount());
    _refreshBannerState();
  }

  void dispose() {
    for (final d in _disposers) {
      d();
    }
    _disposers.clear();
    shouldShowPrompt.dispose();
  }
}
