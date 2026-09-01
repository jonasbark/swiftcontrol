import 'package:bike_control/bluetooth/support_log_buffer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('keeps only the newest [cap] entries', () {
    final buf = SupportLogBuffer(3);
    for (var i = 0; i < 5; i++) {
      buf.add('e$i', at: DateTime(2026, 1, 1, 0, 0, i));
    }
    expect(buf.entries.map((e) => e.entry), ['e2', 'e3', 'e4']);
  });

  test('a wire-trace flood in its own buffer never evicts app-level log entries', () {
    // The regression this guards: app events (shifts, ERG targets, errors) and
    // the verbose DirCon/trainer wire trace used to share one bounded buffer,
    // so a few dozen trace frames per second flushed every high-level event out
    // of a support bundle (the ThinkRider XX Pro +27 bundle was 2000/2000 wire
    // frames, zero app entries). Separate buffers make that impossible.
    final appLog = SupportLogBuffer(500);
    final traceLog = SupportLogBuffer(2000);

    appLog.add('Shifted up to gear 13');
    appLog.add('ERG target: 150 W');
    for (var i = 0; i < 10000; i++) {
      traceLog.add('OUT< frame $i');
    }

    expect(
      appLog.entries.map((e) => e.entry),
      ['Shifted up to gear 13', 'ERG target: 150 W'],
    );
    expect(traceLog.entries, hasLength(2000));
    expect(traceLog.entries.last.entry, 'OUT< frame 9999');
  });
}
