/// The only UTM keys this product captures, matching `UTM_KEYS` in the
/// website's `src/utils/utm.ts`.
const List<String> utmKeys = <String>['utm_source', 'utm_medium', 'utm_campaign', 'utm_content'];

/// Matches `MAX_VALUE_LENGTH` on the website and `MAX_UTM_LENGTH` in the
/// track-analytics edge function, which truncates anything longer anyway.
const int _maxValueLength = 200;

/// Pulls UTM parameters out of a Google Play install referrer.
///
/// The referrer is a bare query string such as
/// `utm_source=facebook&utm_medium=paid`. Organic installs get Play's own
/// value (`utm_source=google-play&utm_medium=organic`), which is worth keeping
/// — it is how paid and organic installs are told apart.
///
/// Throws [FormatException] if the referrer contains malformed percent-encoding.
/// Callers must catch and route that through `recordError`.
Map<String, String> parseInstallReferrer(String? referrer) {
  if (referrer == null || referrer.trim().isEmpty) return const <String, String>{};

  final params = Uri.splitQueryString(referrer);
  final result = <String, String>{};

  for (final key in utmKeys) {
    final raw = params[key];
    if (raw == null) continue;

    var value = raw.trim();
    if (value.length > _maxValueLength) {
      value = value.substring(0, _maxValueLength);
    }
    if (value.isNotEmpty) result[key] = value;
  }

  return result;
}
