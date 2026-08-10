import 'dart:typed_data';

import 'package:bike_control/bluetooth/devices/wheeltop/wheeltop_probe.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(WheeltopProbe.resetRotation);

  const char2 = '6e400002-b5a3-f393-e0a9-e50e24dcca9e';
  const char3 = '6e400003-b5a3-f393-e0a9-e50e24dcca9e';
  const both = [(uuid: char2, withoutResponse: true), (uuid: char3, withoutResponse: false)];

  group('candidate enumeration', () {
    test('all frames on 6e400003 first, then the other characteristic', () {
      final candidates = WheeltopProbe.candidatesFor(typeByte: 0x36, writableCharacteristics: both);

      // 7 frames × 2 characteristics.
      expect(candidates.length, 14);
      // Frame set per characteristic: type-echo, type-ack, type-0x0f-echo,
      // 3-byte XOR echo, 3-byte XOR ack, 09-01-00-00 echo, bare ACK.
      expect(candidates[0].characteristicUuid, char3);
      expect(candidates[0].frame, [0x04, 0x36, 0x10, 0x4a]);
      expect(candidates[1].frame, [0x04, 0x36, 0x11, 0x4b]);
      expect(candidates[2].frame, [0x04, 0x36, 0x0f, 0x49]); // data-informed: pod's 0x0f reply
      expect(candidates[3].frame, [0x04, 0x10, 0x14]);
      expect(candidates[4].frame, [0x04, 0x11, 0x15]);
      expect(candidates[5].frame, [0x09, 0x01, 0x00, 0x00]); // data-informed: pod's verbatim reply
      expect(candidates[6].frame, [0x01]);
      expect(candidates[7].characteristicUuid, char2);
      expect(candidates[7].frame, [0x04, 0x36, 0x10, 0x4a]);
    });

    test('checksums are additive and type-specific', () {
      final candidates = WheeltopProbe.candidatesFor(
        typeByte: 0x38,
        writableCharacteristics: const [(uuid: char3, withoutResponse: false)],
      );
      expect(candidates[0].frame, [0x04, 0x38, 0x10, 0x4c]);
      expect(candidates[1].frame, [0x04, 0x38, 0x11, 0x4d]);
      expect(candidates[2].frame, [0x04, 0x38, 0x0f, 0x4b]); // matches the field-observed reply
    });
  });

  group('rotation', () {
    test('advances one candidate per connection and wraps around', () {
      final first = WheeltopProbe.nextCandidate('pod-a', typeByte: 0x36, writableCharacteristics: both);
      final second = WheeltopProbe.nextCandidate('pod-a', typeByte: 0x36, writableCharacteristics: both);
      expect(first.index, 0);
      expect(second.index, 1);

      for (var i = 2; i < 14; i++) {
        WheeltopProbe.nextCandidate('pod-a', typeByte: 0x36, writableCharacteristics: both);
      }
      final wrapped = WheeltopProbe.nextCandidate('pod-a', typeByte: 0x36, writableCharacteristics: both);
      expect(wrapped.index, 0);
    });

    test('devices rotate independently', () {
      WheeltopProbe.nextCandidate('pod-a', typeByte: 0x36, writableCharacteristics: both);
      final b = WheeltopProbe.nextCandidate('pod-b', typeByte: 0x38, writableCharacteristics: both);
      expect(b.index, 0);
    });
  });

  group('probe lifecycle', () {
    late List<(String, Uint8List, bool)> writes;
    late List<String> logs;
    late DateTime clock;

    WheeltopProbe startProbe() {
      writes = [];
      logs = [];
      clock = DateTime(2026, 7, 13, 12, 0, 0);
      final probe = WheeltopProbe(
        deviceId: 'pod-a',
        typeByte: 0x38,
        writableCharacteristics: const [(uuid: char3, withoutResponse: false)],
        write: (uuid, value, {required withoutResponse}) async => writes.add((uuid, value, withoutResponse)),
        log: logs.add,
        now: () => clock,
      );
      probe.start();
      return probe;
    }

    test('writes the candidate immediately and again per status frame', () async {
      final probe = startProbe();
      expect(writes.length, 1);
      expect(writes.single.$2, Uint8List.fromList([0x04, 0x38, 0x10, 0x4c]));
      expect(logs.any((l) => l.contains('candidate 1/7') && l.contains('started')), isTrue);
      // Outgoing bytes are logged verbatim.
      expect(logs.any((l) => l.contains('tx 6e400003') && l.contains('04 38 10 4c')), isTrue);

      await probe.onStatusFrame();
      await probe.onStatusFrame();
      expect(writes.length, 3);
    });

    test('reports a dropped connection with lifetime and counts', () async {
      final probe = startProbe();
      await probe.onStatusFrame();
      clock = clock.add(const Duration(milliseconds: 3300));
      probe.end();

      expect(logs.last, contains('ended after 3.3s'));
      expect(logs.last, contains('1 status frame(s)'));
      expect(logs.last, isNot(contains('SURVIVED')));
    });

    test('reports survival past the threshold as the likely answer', () {
      final probe = startProbe();
      clock = clock.add(const Duration(seconds: 12));
      probe.end();

      expect(logs.last, contains('SURVIVED 12.0s'));
    });

    test('logs an inbound frame verbatim with slot, length and candidate', () {
      final probe = startProbe();
      probe.logIncoming('6e400003-b5a3-f393-e0a9-e50e24dcca9e', [0x04, 0x38, 0x11, 0x30]);

      expect(logs.last, contains('rx 6e400003'));
      expect(logs.last, contains('04 38 11 30'));
      expect(logs.last, contains('len 4'));
      expect(logs.last, contains('candidate 1/7'));
    });

    test('an empty inbound frame is logged as empty with its length', () {
      final probe = startProbe();
      probe.logIncoming('6e400002-b5a3-f393-e0a9-e50e24dcca9e', const []);

      expect(logs.last, contains('rx 6e400002'));
      expect(logs.last, contains('(empty)'));
      expect(logs.last, contains('len 0'));
    });

    test('a failing write is logged, not thrown', () async {
      final logs = <String>[];
      final probe = WheeltopProbe(
        deviceId: 'pod-b',
        typeByte: 0x38,
        writableCharacteristics: const [(uuid: char3, withoutResponse: false)],
        write: (uuid, value, {required withoutResponse}) async => throw Exception('nope'),
        log: logs.add,
        now: DateTime.now,
      );
      probe.start();
      await probe.onStatusFrame();
      expect(logs.where((l) => l.contains('write failed')), isNotEmpty);
    });
  });
}
