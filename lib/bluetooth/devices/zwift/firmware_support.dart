import 'package:version/version.dart';

/// Parses the leading `major.minor.patch` of a firmware string, tolerating
/// extra trailing components (e.g. Zwift's `1.2.0.24`) and returning null for
/// anything without a numeric leading version. Never throws.
Version? parseLenientFirmwareVersion(String? raw) {
  if (raw == null) return null;
  final match = RegExp(r'^\s*(\d+)(?:\.(\d+))?(?:\.(\d+))?').firstMatch(raw);
  if (match == null) return null;
  final major = int.tryParse(match.group(1) ?? '');
  if (major == null) return null;
  final minor = int.tryParse(match.group(2) ?? '0') ?? 0;
  final patch = int.tryParse(match.group(3) ?? '0') ?? 0;
  return Version(major, minor, patch);
}

/// True when [firmware] is strictly newer than [supported] (both parsed
/// leniently). Any missing or unparseable input yields false — fail safe, so a
/// weird version string never raises a false alarm.
bool isFirmwareBeyondSupported(String? firmware, String? supported) {
  final f = parseLenientFirmwareVersion(firmware);
  final s = parseLenientFirmwareVersion(supported);
  if (f == null || s == null) return false;
  return f > s;
}
