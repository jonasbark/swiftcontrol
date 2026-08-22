import '../../utils/core.dart';
import 'network_check.dart';
import 'network_self_test_result.dart';

/// Persistence for the last network self-test run — one slot, shared across
/// every trainer/target, mirroring how [Settings.getSelfTestResultJson] keeps
/// the per-trainer resistance self-test.
class NetworkSelfTestStore {
  const NetworkSelfTestStore._();

  /// Persist only completed or ≥1-active-probe-cancelled runs: a cancel hit
  /// before a single probe ran (or after only `skipped` rows) carries
  /// nothing worth showing later, so it is dropped rather than overwriting
  /// whatever the previous run left behind.
  static Future<void> save(NetworkSelfTestResult result) async {
    final hasActiveProbe = result.checks.any((check) => check.verdict != NetworkVerdict.skipped);
    if (!result.completed && !hasActiveProbe) {
      return;
    }
    await core.settings.setNetworkSelfTestResultJson(result.toJsonString());
  }

  static NetworkSelfTestResult? load() {
    return NetworkSelfTestResult.tryParse(core.settings.getNetworkSelfTestResultJson());
  }

  /// `'Network self-test:\n<toBundleString()>'` or `''` when none stored —
  /// the caller (`debugText()`) interpolates this as a whole optional block,
  /// so an empty string must add nothing, not even a blank line.
  static String bundleSection() {
    final result = load();
    if (result == null) {
      return '';
    }
    return 'Network self-test:\n${result.toBundleString()}';
  }
}
