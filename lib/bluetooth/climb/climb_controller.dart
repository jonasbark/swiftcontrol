import 'dart:async';

import 'package:bike_control/bluetooth/climb/climb_incline_sink.dart';
import 'package:prop/utils/wahoo_climb.dart';

/// Runs a ~1 Hz loop: read the active bridge's sim grade, pick a sink, and
/// write the clamped incline while the sink follows grade (auto). Flattens once
/// when the grade source disappears after having driven the Climb.
class ClimbController {
  ClimbController({
    required int? Function() gradeProvider,
    required ClimbInclineSink? Function() sinkProvider,
  })  : _gradeProvider = gradeProvider,
        _sinkProvider = sinkProvider;

  final int? Function() _gradeProvider;
  final ClimbInclineSink? Function() _sinkProvider;

  Timer? _timer;
  int? _lastWritten;
  ClimbInclineSink? _lastSink;
  bool _ticking = false;

  void start() {
    _timer ??= Timer.periodic(const Duration(seconds: 1), (_) => tick());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> tick() async {
    if (_ticking) return; // don't overlap if a previous tick's write is still in flight
    _ticking = true;
    try {
      final sink = _sinkProvider();
      if (sink == null) {
        _lastWritten = null;
        _lastSink = null;
        return;
      }
      // A new sink (e.g. a physical Climb replacing the relay) must get a fresh
      // write, so drop the dedup baseline when the sink identity changes.
      if (!identical(sink, _lastSink)) {
        _lastWritten = null;
        _lastSink = sink;
      }

      final grade = _gradeProvider();
      if (grade == null) {
        // Source gone (trainer app left / mode swap): flatten once for safety.
        if (_lastWritten != null && _lastWritten != 0 && sink.followsGrade) {
          if (await sink.writeInclineRaw(0)) _lastWritten = 0;
        }
        return;
      }

      if (!sink.followsGrade) return; // manual hold — device owns the value

      final clamped = grade.clamp(kWahooClimbMinGrade001, kWahooClimbMaxGrade001);
      if (clamped == _lastWritten) return;
      if (await sink.writeInclineRaw(clamped)) _lastWritten = clamped;
    } finally {
      _ticking = false;
    }
  }
}
