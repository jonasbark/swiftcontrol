/// Apple's Local Network privacy permission, which has no status API.
///
/// Denial is silent: Bonjour browses return nothing forever, advertisements
/// never leave the device and LAN sockets simply never see traffic. Nothing
/// throws, so an app that only watches for errors cannot tell "permission is
/// off" from "there is nothing out there". This probes it instead.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Outcome of one Local Network probe.
enum LocalNetworkStatus {
  /// A Bonjour round trip completed, so LAN traffic reaches this process.
  granted,

  /// The platform reported `kDNSServiceErr_PolicyDenied` (-65570).
  denied,

  /// Neither happened before the timeout, or this platform has no such
  /// permission at all.
  ///
  /// Not an error, and explicitly not a denial: a device with no usable
  /// network never completes the round trip even when the permission is fine.
  /// Callers must fail open on this.
  unknown,
}

/// Probes (and, the first time, requests) the Local Network permission.
///
/// The probe is not silent on first use — it triggers the system prompt,
/// which is the point: the alternative is the permission never being asked
/// for until some LAN feature has already failed. Once the user has answered,
/// further probes reuse the decision without prompting again.
class LocalNetworkPermission {
  LocalNetworkPermission._();

  @visibleForTesting
  static const channel = MethodChannel('bike_control/local_network_permission');

  /// Whether this platform gates local network access behind a permission.
  static bool get isSupported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.iOS || defaultTargetPlatform == TargetPlatform.macOS);

  /// Runs one probe, resolving within roughly [timeout].
  ///
  /// Throws [PlatformException] if the native probe could not be built; a
  /// missing plugin (older build, unsupported platform) yields [unknown]
  /// rather than an error, because "we cannot tell" is the honest answer.
  static Future<LocalNetworkStatus> check({
    Duration timeout = const Duration(seconds: 4),
  }) async {
    if (!isSupported) return LocalNetworkStatus.unknown;
    final String? outcome;
    try {
      outcome = await channel
          .invokeMethod<String>('check', {'timeoutMs': timeout.inMilliseconds})
          // The native side has its own deadline; this only catches a probe
          // that wedged entirely. Without it a caller awaiting the result
          // would wait forever, and so would everyone queued behind it.
          .timeout(timeout + const Duration(seconds: 2), onTimeout: () => null);
    } on MissingPluginException {
      return LocalNetworkStatus.unknown;
    }
    return switch (outcome) {
      'granted' => LocalNetworkStatus.granted,
      'denied' => LocalNetworkStatus.denied,
      _ => LocalNetworkStatus.unknown,
    };
  }

  /// Opens the place where the user can flip the toggle: BikeControl's own
  /// settings page on iOS, the Privacy & Security pane on macOS.
  static Future<void> openSettings() async {
    if (!isSupported) return;
    try {
      await channel.invokeMethod<void>('openSettings');
    } on MissingPluginException {
      // Nothing to open on a build without the plugin.
    }
  }
}
