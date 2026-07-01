import 'dart:async';

import 'package:bike_control/bluetooth/incline/incline_controller.dart';
import 'package:bike_control/bluetooth/incline/incline_sink.dart';
import 'package:flutter_test/flutter_test.dart';

class _SlowSink implements InclineSink {
  _SlowSink({required this.followsGrade});
  @override
  bool followsGrade;
  int calls = 0;
  final Completer<void> gate = Completer<void>();
  @override
  Future<bool> writeInclineRaw(int g) async {
    calls++;
    await gate.future;
    return true;
  }
}

class _FakeSink implements InclineSink {
  _FakeSink(this.followsGrade);
  @override
  bool followsGrade;
  final List<int> writes = [];
  @override
  Future<bool> writeInclineRaw(int g) async {
    writes.add(g);
    return true;
  }
}

void main() {
  group('InclineController.tick', () {
    test('writes the current grade to the sink in auto mode', () async {
      final sink = _FakeSink(true);
      final c = InclineController(gradeProvider: () => 600, sinkProvider: () => sink);
      await c.tick();
      expect(sink.writes, [600]);
    });

    test('does not write when the sink is in manual hold', () async {
      final sink = _FakeSink(false);
      final c = InclineController(gradeProvider: () => 600, sinkProvider: () => sink);
      await c.tick();
      expect(sink.writes, isEmpty);
    });

    test('clamps to the incline range', () async {
      final sink = _FakeSink(true);
      final c = InclineController(gradeProvider: () => 9000, sinkProvider: () => sink);
      await c.tick();
      expect(sink.writes, [2000]);
    });

    test('deduplicates unchanged grades', () async {
      final sink = _FakeSink(true);
      var g = 600;
      final c = InclineController(gradeProvider: () => g, sinkProvider: () => sink);
      await c.tick();
      await c.tick();
      g = 700;
      await c.tick();
      expect(sink.writes, [600, 700]);
    });

    test('no grade source: no write', () async {
      final sink = _FakeSink(true);
      final c = InclineController(gradeProvider: () => null, sinkProvider: () => sink);
      await c.tick();
      expect(sink.writes, isEmpty);
    });

    test('flattens once when the grade source disappears after driving', () async {
      final sink = _FakeSink(true);
      int? g = 600;
      final c = InclineController(gradeProvider: () => g, sinkProvider: () => sink);
      await c.tick();
      g = null;
      await c.tick();
      await c.tick();
      expect(sink.writes, [600, 0]);
    });

    test('writes to a newly-swapped sink even if the grade is unchanged', () async {
      final sinkA = _FakeSink(true);
      final sinkB = _FakeSink(true);
      InclineSink current = sinkA;
      final c = InclineController(gradeProvider: () => 600, sinkProvider: () => current);
      await c.tick();
      expect(sinkA.writes, [600]);
      current = sinkB;
      await c.tick();
      expect(sinkB.writes, [600]); // dedup reset on sink change
    });

    test('does not overlap ticks while a write is in flight', () async {
      final sink = _SlowSink(followsGrade: true);
      final c = InclineController(gradeProvider: () => 600, sinkProvider: () => sink);
      final first = c.tick(); // enters writeInclineRaw, awaits the gate
      await c.tick(); // reentrant — should return immediately, no second call
      expect(sink.calls, 1);
      sink.gate.complete();
      await first;
    });
  });
}
