import 'package:bike_control/utils/analytics/install_referrer_parser.dart';

/// Turns a stored Play install referrer into RevenueCat subscriber attributes.
///
/// RevenueCat reserves `$campaign`, `$mediaSource`, `$adGroup` and `$ad` for
/// attribution; setting them is what makes trial-to-paid conversion and revenue
/// break down by campaign in its dashboards, rather than only cost-per-install
/// being measurable. `utm_medium` has no reserved equivalent, so it goes in a
/// namespaced custom attribute.
///
/// `$adGroup` and `$ad` both take `utm_content`: that is the only ad-level
/// identifier the funnel carries end to end, and it is what `analytics_events`
/// joins a `download_clicked` to an `app_install` on.
///
/// Throws [ArgumentError] on malformed percent-encoding, matching
/// [parseInstallReferrer]. Callers must catch and route that through
/// `recordError`.
Map<String, String> campaignAttributes(String? referrer) {
  final utms = parseInstallReferrer(referrer);
  if (utms.isEmpty) return const <String, String>{};

  final campaign = utms['utm_campaign'];
  final source = utms['utm_source'];
  final content = utms['utm_content'];
  final medium = utms['utm_medium'];

  return <String, String>{
    if (campaign != null) r'$campaign': campaign,
    if (source != null) r'$mediaSource': source,
    if (content != null) r'$adGroup': content,
    if (content != null) r'$ad': content,
    if (medium != null) 'bikecontrol_utm_medium': medium,
  };
}
