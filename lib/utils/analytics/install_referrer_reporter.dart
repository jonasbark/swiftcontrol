import 'package:bike_control/main.dart' show recordError;
import 'package:bike_control/utils/analytics/install_referrer_parser.dart';
import 'package:play_install_referrer/play_install_referrer.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Where the install referrer comes from. Abstracted so the reporter can be
/// tested without the Play Store plugin, which needs a real device.
abstract class InstallReferrerSource {
  Future<String?> read();
}

/// Reads the referrer from the Google Play Install Referrer API.
class PlayInstallReferrerSource implements InstallReferrerSource {
  @override
  Future<String?> read() async {
    try {
      final details = await PlayInstallReferrer.installReferrer;
      return details.installReferrer;
    } catch (e, s) {
      // Expected on sideloaded builds, emulators without Play Services, and
      // when the referrer service is briefly unavailable. Recorded rather than
      // swallowed, then treated as "no referrer" so the install still counts.
      recordError(e, s, context: 'PlayInstallReferrerSource.read');
      return null;
    }
  }
}

/// Reports the Play install referrer exactly once per installation.
///
/// Runs on Android only. The event lands in the same `analytics_events` table
/// the website writes to, so an install joins its originating ad click on
/// `utm_content`.
class InstallReferrerReporter {
  /// [source] reads the raw referrer, [prefs] persists the once-only flag,
  /// and [send] posts the resulting event body to analytics.
  InstallReferrerReporter({required this.source, required this.prefs, required this.send});

  final InstallReferrerSource source;
  final SharedPreferences prefs;

  /// Posts the event body to the `track-analytics` edge function. Injected so
  /// tests do not need a Supabase client.
  final Future<void> Function(Map<String, dynamic> body) send;

  static const String reportedKey = 'install_referrer_reported';

  /// Where the raw referrer is kept after it has been reported. The Play
  /// Install Referrer API is only readable once, early in an install's life,
  /// but RevenueCat subscriber attributes have to be re-sent on every launch —
  /// so the value has to survive past the one-shot read.
  static const String referrerKey = 'install_referrer';

  Future<void> reportOnce() async {
    if (prefs.getBool(reportedKey) ?? false) return;

    final referrer = await source.read();
    final utms = parseInstallReferrer(referrer);

    await send(<String, dynamic>{
      'eventType': 'app_install',
      'downloadPlatform': 'android',
      'referrerUrl': referrer,
      ...utms,
    });

    // Only after a successful send, so a failed report is retried next launch
    // rather than being lost.
    if (referrer != null && referrer.isNotEmpty) {
      await prefs.setString(referrerKey, referrer);
    }
    await prefs.setBool(reportedKey, true);
  }
}
