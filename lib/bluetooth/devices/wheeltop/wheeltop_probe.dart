import 'package:flutter/foundation.dart';

/// A writable NUS characteristic a candidate can target.
typedef ProbeTarget = ({String uuid, bool withoutResponse});

/// Writes [value] to [characteristicUuid] on the pod.
typedef ProbeWrite =
    Future<void> Function(String characteristicUuid, Uint8List value, {required bool withoutResponse});

/// One reply-candidate: the bytes to write and where to write them.
class ProbeCandidate {
  const ProbeCandidate({
    required this.frame,
    required this.characteristicUuid,
    required this.withoutResponse,
    required this.index,
    required this.total,
  });

  final List<int> frame;
  final String characteristicUuid;
  final bool withoutResponse;
  final int index;
  final int total;

  String get _frameHex => frame.map((e) => e.toRadixString(16).padLeft(2, '0')).join();

  String get label =>
      'candidate ${index + 1}/$total [$_frameHex → ${characteristicUuid.substring(0, 8)}]';
}

/// Keepalive-reply experiment for WHEELTOP TX pods.
///
/// TX firmware sends a `04 type 10 sum` status frame at 1 Hz after connect
/// and drops the link after three unanswered frames — presumably the rear
/// derailleur replies with something we have not captured yet. Every
/// connection cycle this probe picks the next reply candidate, writes it once
/// right after subscription and again for each status frame, and logs how
/// long the connection survived. A lifetime past [survivalThreshold] marks
/// the candidate as the likely answer. Worst case per attempt is the
/// disconnect that happens anyway.
///
/// One instance lives per connection; the candidate rotation persists across
/// reconnects (per pod id) for the app session.
class WheeltopProbe {
  WheeltopProbe({
    required this.deviceId,
    required int typeByte,
    required List<ProbeTarget> writableCharacteristics,
    required ProbeWrite write,
    required void Function(String message) log,
    DateTime Function() now = DateTime.now,
  }) : _write = write,
       _log = log,
       _now = now,
       candidate = nextCandidate(
         deviceId,
         typeByte: typeByte,
         writableCharacteristics: writableCharacteristics,
       );

  static const Duration survivalThreshold = Duration(seconds: 5);

  /// Next candidate index per pod id — survives reconnects (each reconnect
  /// builds a fresh device object and probe) but not an app restart.
  static final Map<String, int> _rotation = {};

  @visibleForTesting
  static void resetRotation() => _rotation.clear();

  final String deviceId;
  final ProbeCandidate candidate;
  final ProbeWrite _write;
  final void Function(String message) _log;
  final DateTime Function() _now;

  late final DateTime _startedAt = _now();
  int _statusFrames = 0;
  int _writes = 0;
  bool _ended = false;

  /// All candidates for a pod: every reply frame tried on `6e400003` (the
  /// slot a stock Nordic UART peripheral receives on) before any other
  /// writable characteristic.
  static List<ProbeCandidate> candidatesFor({
    required int typeByte,
    required List<ProbeTarget> writableCharacteristics,
  }) {
    int sum(int code) => (0x04 + typeByte + code) & 0xff;
    final frames = <List<int>>[
      [0x04, typeByte, 0x10, sum(0x10)], // echo the status frame
      [0x04, typeByte, 0x11, sum(0x11)], // ack as code+1
      [0x04, 0x10, 0x04 ^ 0x10], // 3-byte XOR shape, echo
      [0x04, 0x11, 0x04 ^ 0x11], // 3-byte XOR shape, ack
      [0x01], // bare ACK byte
    ];

    final ordered = [
      ...writableCharacteristics.where((c) => c.uuid.toLowerCase().startsWith('6e400003')),
      ...writableCharacteristics.where((c) => !c.uuid.toLowerCase().startsWith('6e400003')),
    ];

    final total = ordered.length * frames.length;
    var index = 0;
    return [
      for (final target in ordered)
        for (final frame in frames)
          ProbeCandidate(
            frame: frame,
            characteristicUuid: target.uuid,
            withoutResponse: target.withoutResponse,
            index: index++,
            total: total,
          ),
    ];
  }

  /// The next candidate in this pod's rotation, advancing it.
  static ProbeCandidate nextCandidate(
    String deviceId, {
    required int typeByte,
    required List<ProbeTarget> writableCharacteristics,
  }) {
    final candidates = candidatesFor(
      typeByte: typeByte,
      writableCharacteristics: writableCharacteristics,
    );
    final index = (_rotation[deviceId] ?? 0) % candidates.length;
    _rotation[deviceId] = index + 1;
    return candidates[index];
  }

  /// Logs the chosen candidate and fires the first write — some firmware may
  /// expect the central to speak first, before any status frame arrives.
  void start() {
    _startedAt; // materialize the connection start time
    _log('WHEELTOP PROBE: ${candidate.label} started');
    _sendCandidate();
  }

  /// A `04 type 10 sum` status frame arrived — answer it with the candidate.
  Future<void> onStatusFrame() async {
    _statusFrames++;
    await _sendCandidate();
  }

  /// Any frame that is not a button event or the known status frame — while
  /// probing, that is potentially the pod reacting to a candidate. Logs the
  /// slot it arrived on and the byte length, so an empty/artifact frame is
  /// distinguishable from a real reply and its characteristic is visible.
  void onUnexpectedFrame(String characteristicUuid, List<int> bytes) {
    final slot = characteristicUuid.length >= 8 ? characteristicUuid.substring(0, 8) : characteristicUuid;
    final hex = bytes.isEmpty ? '(empty)' : bytes.map((e) => e.toRadixString(16).padLeft(2, '0')).join(' ');
    _log(
      'WHEELTOP PROBE: pod sent $hex (len ${bytes.length}) on $slot during ${candidate.label} — capture this!',
    );
  }

  /// The connection ended — record the verdict for this candidate.
  void end() {
    if (_ended) return;
    _ended = true;
    final lifetime = _now().difference(_startedAt);
    final seconds = (lifetime.inMilliseconds / 1000).toStringAsFixed(1);
    if (lifetime >= survivalThreshold) {
      _log('WHEELTOP PROBE: ${candidate.label} SURVIVED ${seconds}s — likely answer!');
    } else {
      _log(
        'WHEELTOP PROBE: ${candidate.label} ended after ${seconds}s, '
        '$_statusFrames status frame(s), $_writes write(s) — no effect',
      );
    }
  }

  Future<void> _sendCandidate() async {
    try {
      await _write(
        candidate.characteristicUuid,
        Uint8List.fromList(candidate.frame),
        withoutResponse: candidate.withoutResponse,
      );
      _writes++;
    } catch (e, stackTrace) {
      _log('WHEELTOP PROBE: write failed for ${candidate.label}: $e\n$stackTrace');
    }
  }
}
