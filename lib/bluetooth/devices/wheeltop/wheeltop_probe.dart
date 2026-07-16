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
      [0x04, typeByte, 0x0f, sum(0x0f)], // echo the pod's own reply opcode 0x0f (from field log)
      [0x04, 0x10, 0x04 ^ 0x10], // 3-byte XOR shape, echo
      [0x04, 0x11, 0x04 ^ 0x11], // 3-byte XOR shape, ack
      [0x09, 0x01, 0x00, 0x00], // echo the pod's other observed reply verbatim
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

  static String _slot(String uuid) => uuid.length >= 8 ? uuid.substring(0, 8) : uuid;

  static String _hex(List<int> bytes) =>
      bytes.isEmpty ? '(empty)' : bytes.map((e) => e.toRadixString(16).padLeft(2, '0')).join(' ');

  /// Logs every inbound frame verbatim — slot, byte length and bytes — while
  /// probing, so the support log is a full transcript of what the pod sends
  /// (an empty artifact on the write slot vs a real reply on another slot).
  void logIncoming(String characteristicUuid, List<int> bytes) {
    _log('WHEELTOP PROBE rx ${_slot(characteristicUuid)} len ${bytes.length}: ${_hex(bytes)} (${candidate.label})');
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
    _log('WHEELTOP PROBE tx ${_slot(candidate.characteristicUuid)}: ${_hex(candidate.frame)} (${candidate.label})');
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
