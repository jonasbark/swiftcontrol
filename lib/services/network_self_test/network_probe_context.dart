import 'dart:io';

import 'package:prop/mdns/mdns_responder.dart' show MdnsQueryLogEntry;

import '../../bluetooth/devices/openbikecontrol/obp_mdns_backend.dart';
import '../debug_diagnostics.dart';

/// Pushed by the guided-watch probe (a later task) as it polls, so the engine
/// can update the "watching..." UI live instead of only learning the outcome
/// once the whole probe returns.
typedef WatchProgressCallback = void Function(WatchProgress progress);

/// One tick of the guided-watch probe: what has been observed on the wire so
/// far, and how long the watch window has left to run.
class WatchProgress {
  final bool browsed;
  final bool resolved;
  final int addressAsks;
  final bool connected;
  final Duration remaining;

  const WatchProgress({
    required this.browsed,
    required this.resolved,
    required this.addressAsks,
    required this.connected,
    required this.remaining,
  });
}

/// Everything a probe function needs to do its job, injected so the checks
/// stay pure functions over data instead of reaching into `core` or touching
/// the network themselves directly. Built once per self-test run by the
/// engine (a later task); the passive probes only read [snapshot] and the
/// plain fields, but the function seams below exist here too so every probe
/// — including the active/OS-level ones landing in later tasks — shares one
/// context shape.
class NetworkProbeContext {
  /// The one `DebugDiagnostics.gather()` snapshot the passive checks read.
  /// Null when the gather itself threw; probes fall back to `unknown`.
  final DebugDiagnostics? snapshot;

  /// The error `DebugDiagnostics.gather()` threw. Only meaningful when
  /// [snapshot] is null; surfaced in a check's detail map.
  final Object? snapshotError;

  /// `core.obpMdnsEmulator.isStarted.value`.
  final bool emulatorStarted;

  /// `core.obpMdnsEmulator.isConnected.value`.
  final bool trainerAppConnected;

  /// Live read of the same connected state as [trainerAppConnected], sampled
  /// fresh on every guided-watch tick instead of once at context build time
  /// — the watch polls for minutes, so a snapshot taken before the user even
  /// opens the trainer app would never observe the connect.
  final bool Function() trainerAppConnectedNow;

  /// `core.settings.getTrainerApp()?.name`.
  final String? trainerAppName;

  /// `core.obpMdnsEmulator.activeBackend`.
  final ObpMdnsBackend backend;

  /// `core.obpMdnsEmulator.advertisedHostname`.
  final String? advertisedHostname;

  /// `Platform.operatingSystem`-shaped: 'windows' | 'macos' | 'linux' |
  /// 'android' | 'ios' | 'web'.
  final String platform;

  /// DNS resolution seam, for the hostname-resolution probe.
  final Future<List<InternetAddress>> Function(String host) resolve;

  /// TCP connect seam, for the self-connect probe; throws on failure.
  final Future<void> Function(String address, int port) tcpProbe;

  /// `Process.run` seam, for the Windows shell probes.
  final Future<ProcessResult> Function(String executable, List<String> arguments) runProcess;

  /// Returns the responder's received-query log at call time.
  final List<MdnsQueryLogEntry> Function() queryLog;

  /// `Future.delayed` seam so a probe's polling loop is instant under test.
  final Future<void> Function(Duration duration) sleep;

  /// `DateTime.now` seam, for a probe's countdown.
  final DateTime Function() now;

  /// Called by the guided-watch probe as it polls, so the engine can push
  /// live progress into the UI.
  final WatchProgressCallback onWatchProgress;

  const NetworkProbeContext({
    required this.snapshot,
    required this.snapshotError,
    required this.emulatorStarted,
    required this.trainerAppConnected,
    required this.trainerAppConnectedNow,
    required this.trainerAppName,
    required this.backend,
    required this.advertisedHostname,
    required this.platform,
    required this.resolve,
    required this.tcpProbe,
    required this.runProcess,
    required this.queryLog,
    required this.sleep,
    required this.now,
    required this.onWatchProgress,
  });
}
