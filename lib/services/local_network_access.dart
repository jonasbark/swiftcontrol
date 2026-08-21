/// Cached, app-wide view of Apple's Local Network permission.
///
/// Denial is the single most common cause of "BikeControl can't see my
/// trainer app" on iOS and macOS, and it fails completely silently — so this
/// is checked up front instead of being inferred from an empty discovery scan.
library;

import 'dart:async';

import 'package:bike_control/main.dart' show recordError;
import 'package:flutter/foundation.dart';
import 'package:local_network_permission/local_network_permission.dart';

export 'package:local_network_permission/local_network_permission.dart' show LocalNetworkStatus;

class LocalNetworkAccess {
  LocalNetworkAccess._();

  /// Long enough for a Bonjour round trip on a busy network, short enough not
  /// to stall the tile the user just tapped.
  static const probeTimeout = Duration(seconds: 3);

  /// A probe costs a full network round trip and `getStatus()` runs on every
  /// tile mount, tap and app resume, so results are reused for this long. The
  /// answer can change behind our back (System Settings), which is what
  /// [invalidate] and the short window are for.
  static const cacheDuration = Duration(seconds: 30);

  @visibleForTesting
  static DateTime Function() now = DateTime.now;

  static LocalNetworkStatus? _cached;
  static DateTime? _cachedAt;
  static Future<LocalNetworkStatus>? _inFlight;

  /// The last known status without probing, or null if nothing is cached.
  static LocalNetworkStatus? get cached => _isFresh ? _cached : null;

  static bool get _isFresh {
    final at = _cachedAt;
    return _cached != null && at != null && now().difference(at) < cacheDuration;
  }

  /// The current status, probing only when the cache is stale or [force].
  ///
  /// Concurrent callers share a single probe: two overlapping probes would
  /// advertise the same Bonjour type twice and could resolve each other.
  static Future<LocalNetworkStatus> status({bool force = false}) {
    if (!force && _isFresh) return Future.value(_cached);
    final inFlight = _inFlight;
    if (inFlight != null) return inFlight;

    final probe = _probe();
    _inFlight = probe;
    return probe.whenComplete(() {
      if (identical(_inFlight, probe)) _inFlight = null;
    });
  }

  static Future<LocalNetworkStatus> _probe() async {
    LocalNetworkStatus result;
    try {
      result = await LocalNetworkPermission.check(timeout: probeTimeout);
    } catch (e, s) {
      recordError(e, s, context: 'LocalNetworkAccess.probe');
      // A broken probe must not lock the user out of their trainer app.
      result = LocalNetworkStatus.unknown;
    }
    _cached = result;
    _cachedAt = now();
    return result;
  }

  /// Drops the cache, so the next [status] re-probes.
  ///
  /// Call this whenever the user has been somewhere they could have changed
  /// the answer — the System Settings trip in particular.
  static void invalidate() {
    _cached = null;
    _cachedAt = null;
  }

  /// Whether local-network features should be allowed to run.
  ///
  /// Fails open on [LocalNetworkStatus.unknown]: that means the probe could
  /// not tell (no usable network, no plugin in this build), and treating it as
  /// a denial would block setups that work fine.
  static Future<bool> isUsable({bool force = false}) async {
    return await status(force: force) != LocalNetworkStatus.denied;
  }

  @visibleForTesting
  static void resetForTest() {
    invalidate();
    _inFlight = null;
    now = DateTime.now;
  }
}
