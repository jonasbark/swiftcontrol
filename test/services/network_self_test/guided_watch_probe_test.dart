import 'dart:io';

import 'package:bike_control/bluetooth/devices/openbikecontrol/obp_mdns_backend.dart';
import 'package:bike_control/services/network_self_test/network_check.dart';
import 'package:bike_control/services/network_self_test/network_probe_context.dart';
import 'package:bike_control/services/network_self_test/probes/guided_watch_probe.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prop/mdns/mdns_responder.dart';

const _defaultWindow = Duration(seconds: 3);
const _defaultTick = Duration(seconds: 1);

/// A context with no-op seams; every field can be overridden per test.
///
/// `now` defaults to a fake clock that advances by exactly [_defaultTick] on
/// every call — since [ctx]'s `sleep` never actually waits, this is what
/// makes the watch loop's "window elapsed" exit deterministic instead of
/// looping forever.
NetworkProbeContext ctx({
  ObpMdnsBackend backend = ObpMdnsBackend.platformDefault,
  String? advertisedHostname = 'BikeControl.local',
  List<MdnsQueryLogEntry> Function()? queryLog,
  bool Function()? trainerAppConnectedNow,
  WatchProgressCallback? onWatchProgress,
}) {
  var nowCalls = 0;
  final base = DateTime(2026, 8, 21);
  return NetworkProbeContext(
    snapshot: null,
    snapshotError: null,
    emulatorStarted: true,
    trainerAppConnected: false,
    trainerAppConnectedNow: trainerAppConnectedNow ?? () => false,
    trainerAppName: null,
    backend: backend,
    advertisedHostname: advertisedHostname,
    platform: 'macos',
    resolve: (host) async => const [],
    tcpProbe: (address, port) async {},
    runProcess: (executable, arguments) async => ProcessResult(0, 0, '', ''),
    queryLog: queryLog ?? () => const [],
    sleep: (d) async {},
    now: () => base.add(_defaultTick * nowCalls++),
    onWatchProgress: onWatchProgress ?? (progress) {},
  );
}

MdnsQueryLogEntry _entry(List<String> questions, {int count = 1}) => MdnsQueryLogEntry(
  at: DateTime(2026, 8, 21),
  source: '192.168.1.50',
  sourcePort: 5353,
  wantsUnicast: false,
  questions: questions,
  answeredUnicast: false,
  answeredMulticast: true,
  count: count,
);

/// Builds a `queryLog` closure driven by a scripted list of "snapshots" — one
/// per tick the watch is expected to observe, in growing order. Once the
/// script is exhausted, further calls keep returning the last snapshot
/// unchanged (steady state — no more new asks), so tests don't need to guess
/// the exact number of ticks the watch loop runs before the window elapses.
List<MdnsQueryLogEntry> Function() _scriptedLog(List<List<MdnsQueryLogEntry>> snapshots) {
  var call = 0;
  return () {
    final index = call < snapshots.length ? call : snapshots.length - 1;
    call++;
    return snapshots[index];
  };
}

void main() {
  group('guidedWatchCheck', () {
    test('pass: connects immediately, before any query is observed', () async {
      final progress = <WatchProgress>[];
      final check = await guidedWatchCheck(
        ctx(trainerAppConnectedNow: () => true, onWatchProgress: progress.add),
        window: _defaultWindow,
        tick: _defaultTick,
      );
      expect(check.id, NetworkCheckId.guidedWatch);
      expect(check.verdict, NetworkVerdict.pass);
      expect(progress, isNotEmpty);
      expect(progress.first.connected, isTrue);
    });

    test('fail: >= 3 address asks and never connects, useOsResponderForObc under platformDefault', () async {
      final entry = _entry(const ['A BikeControl.local']);
      var calls = 0;
      List<MdnsQueryLogEntry> queryLog() {
        // The responder mutates the same folded entry in place; each repeat
        // bumps `count` without a new entry appearing in the list.
        if (calls > 0) entry.count++;
        calls++;
        return [entry];
      }

      final check = await guidedWatchCheck(
        ctx(backend: ObpMdnsBackend.platformDefault, queryLog: queryLog),
        window: _defaultWindow,
        tick: _defaultTick,
      );
      expect(check.verdict, NetworkVerdict.fail);
      expect(check.detail['addressAsks'], isNotNull);
      expect(int.parse(check.detail['addressAsks']!), greaterThanOrEqualTo(3));
      expect(check.fixes, contains(NetworkFixId.useOsResponderForObc));
    });

    test('fail: no query arrives at all, switchToLocal', () async {
      final check = await guidedWatchCheck(ctx(queryLog: () => const []), window: _defaultWindow, tick: _defaultTick);
      expect(check.verdict, NetworkVerdict.fail);
      expect(check.detail['hint'], 'no query arrived');
      expect(check.fixes, contains(NetworkFixId.switchToLocal));
    });

    test('warn: browsed but never resolved', () async {
      final browse = _entry(const ['PTR _openbikecontrol._tcp.local']);
      final check = await guidedWatchCheck(
        ctx(queryLog: _scriptedLog([const [], [browse]])),
        window: _defaultWindow,
        tick: _defaultTick,
      );
      expect(check.verdict, NetworkVerdict.warn);
    });

    test('warn: browsed and resolved but no address asks and never connected', () async {
      final browse = _entry(const ['PTR _openbikecontrol._tcp.local']);
      final resolve = _entry(const ['SRV BikeControl._openbikecontrol._tcp.local']);
      final check = await guidedWatchCheck(
        ctx(queryLog: _scriptedLog([const [], [browse], [browse, resolve]])),
        window: _defaultWindow,
        tick: _defaultTick,
      );
      expect(check.verdict, NetworkVerdict.warn);
      expect(check.detail['note'], 'found and resolved, never connected');
    });

    test('skipped: cancelled mid-watch', () async {
      final check = await guidedWatchCheck(
        ctx(),
        window: _defaultWindow,
        tick: _defaultTick,
        isCancelled: () => true,
      );
      expect(check.verdict, NetworkVerdict.skipped);
      expect(check.detail['reason'], 'skipped');
    });

    test('pass: osResponder backend, connects', () async {
      final check = await guidedWatchCheck(
        ctx(backend: ObpMdnsBackend.osResponder, trainerAppConnectedNow: () => true),
        window: _defaultWindow,
        tick: _defaultTick,
      );
      expect(check.verdict, NetworkVerdict.pass);
    });

    test('warn: osResponder backend, never connects — only the TCP accept is observable', () async {
      final check = await guidedWatchCheck(
        ctx(backend: ObpMdnsBackend.osResponder),
        window: _defaultWindow,
        tick: _defaultTick,
      );
      expect(check.verdict, NetworkVerdict.warn);
      expect(check.detail['note'], contains('TCP accept'));
    });

    test('count increase on an existing entry (no new list entry) still counts as a new ask', () async {
      final entry = _entry(const ['AAAA BikeControl.local'], count: 1);
      var calls = 0;
      List<MdnsQueryLogEntry> queryLog() {
        // Same object every call: the list never grows, only `count` climbs
        // — exactly how the responder folds repeated identical queries.
        if (calls > 0) entry.count++;
        calls++;
        return [entry];
      }

      final check = await guidedWatchCheck(ctx(queryLog: queryLog), window: _defaultWindow, tick: _defaultTick);
      expect(check.verdict, NetworkVerdict.fail);
      expect(int.parse(check.detail['addressAsks']!), greaterThanOrEqualTo(3));
    });
  });
}
