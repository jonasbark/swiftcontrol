import 'package:prop/mdns/mdns_responder.dart' show MdnsQueryLogEntry;

import '../../../bluetooth/devices/openbikecontrol/obp_mdns_backend.dart';
import '../network_check.dart';
import '../network_probe_context.dart';

/// Check 9: "press the button" — prompts the user to open the trainer app's
/// pairing screen and tap BikeControl, then watches what actually crosses the
/// wire for up to [window], polling every [tick]. Unlike the other probes
/// this one is driven by a loop rather than a single I/O call, so it needs
/// its own seams: [NetworkProbeContext.queryLog] (what the responder saw),
/// [NetworkProbeContext.trainerAppConnectedNow] (sampled fresh every tick,
/// not the fixed snapshot on [NetworkProbeContext.trainerAppConnected]) and
/// [NetworkProbeContext.sleep]/[NetworkProbeContext.now] so tests can drive
/// it without a real clock.
Future<NetworkCheck> guidedWatchCheck(
  NetworkProbeContext ctx, {
  Duration window = const Duration(seconds: 60),
  Duration tick = const Duration(milliseconds: 500),
  bool Function()? isCancelled,
}) async {
  final osResponder = ctx.backend == ObpMdnsBackend.osResponder;
  final start = ctx.now();

  // Under the OS responder, OBC's own advertisement never touches our
  // responder's query log (the OS answers it), so there is nothing to browse
  // for there — skip reading it and classify on `connected` alone below.
  var seenLength = 0;
  var lastCounts = <int>[];
  if (!osResponder) {
    final baseline = ctx.queryLog();
    seenLength = baseline.length;
    lastCounts = [for (final entry in baseline) entry.count];
  }

  var browsed = false;
  var resolved = false;
  var addressAsks = 0;

  while (true) {
    if (isCancelled != null && isCancelled()) {
      return const NetworkCheck(
        id: NetworkCheckId.guidedWatch,
        verdict: NetworkVerdict.skipped,
        detail: {'reason': 'skipped'},
      );
    }

    if (!osResponder) {
      final log = ctx.queryLog();

      // Genuinely new entries appended since the last read.
      final newEntries = <MdnsQueryLogEntry>[if (log.length > seenLength) ...log.sublist(seenLength)];

      // The responder folds repeated identical queries into one entry and
      // just bumps its `count` instead of appending — a count increase on an
      // already-seen address entry is just as real an ask as a new entry.
      for (var i = 0; i < seenLength && i < log.length; i++) {
        final entry = log[i];
        final previousCount = i < lastCounts.length ? lastCounts[i] : entry.count;
        if (entry.count > previousCount && _isAddressEntry(entry, ctx.advertisedHostname)) {
          newEntries.add(entry);
        }
      }

      for (final entry in newEntries) {
        for (final question in entry.questions) {
          if (question.startsWith('PTR _openbikecontrol') || question.startsWith('PTR _wahoo-fitness-tnp')) {
            browsed = true;
          } else if ((question.startsWith('SRV ') || question.startsWith('TXT ')) &&
              question.contains('BikeControl')) {
            resolved = true;
          } else if (_isAddressQuestion(question, ctx.advertisedHostname)) {
            addressAsks++;
          }
        }
      }

      seenLength = log.length;
      lastCounts = [for (final entry in log) entry.count];
    }

    final connected = ctx.trainerAppConnectedNow();
    final elapsed = ctx.now().difference(start);
    final remaining = window - elapsed;
    ctx.onWatchProgress(
      WatchProgress(
        browsed: browsed,
        resolved: resolved,
        addressAsks: addressAsks,
        connected: connected,
        remaining: remaining.isNegative ? Duration.zero : remaining,
      ),
    );

    if (connected) {
      return const NetworkCheck(id: NetworkCheckId.guidedWatch, verdict: NetworkVerdict.pass);
    }

    if (elapsed >= window) {
      break;
    }

    await ctx.sleep(tick);
  }

  if (osResponder) {
    return const NetworkCheck(
      id: NetworkCheckId.guidedWatch,
      verdict: NetworkVerdict.warn,
      detail: {'note': 'OS responder answers queries; only the TCP accept is visible'},
    );
  }

  if (addressAsks >= 3) {
    return NetworkCheck(
      id: NetworkCheckId.guidedWatch,
      verdict: NetworkVerdict.fail,
      detail: {'addressAsks': '$addressAsks'},
      fixes: [if (ctx.backend == ObpMdnsBackend.platformDefault) NetworkFixId.useOsResponderForObc],
    );
  }

  if (!browsed) {
    return const NetworkCheck(
      id: NetworkCheckId.guidedWatch,
      verdict: NetworkVerdict.fail,
      detail: {'hint': 'no query arrived'},
      fixes: [NetworkFixId.switchToLocal],
    );
  }

  if (!resolved) {
    return const NetworkCheck(id: NetworkCheckId.guidedWatch, verdict: NetworkVerdict.warn);
  }

  return const NetworkCheck(
    id: NetworkCheckId.guidedWatch,
    verdict: NetworkVerdict.warn,
    detail: {'note': 'found and resolved, never connected'},
  );
}

/// True when [question] (e.g. `'A BikeControl.local'`) asks for an A/AAAA
/// record matching [hostname] (e.g. `'BikeControl.local'`), comparing with
/// the `.local` suffix stripped, case-insensitively.
bool _isAddressQuestion(String question, String? hostname) {
  if (hostname == null) return false;
  final String name;
  if (question.startsWith('A ')) {
    name = question.substring(2);
  } else if (question.startsWith('AAAA ')) {
    name = question.substring(5);
  } else {
    return false;
  }
  return _stripLocal(name) == _stripLocal(hostname);
}

bool _isAddressEntry(MdnsQueryLogEntry entry, String? hostname) =>
    entry.questions.any((question) => _isAddressQuestion(question, hostname));

String _stripLocal(String value) {
  final lower = value.trim().toLowerCase();
  const suffix = '.local';
  return lower.endsWith(suffix) ? lower.substring(0, lower.length - suffix.length) : lower;
}
