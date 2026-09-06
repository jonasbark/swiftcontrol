import 'package:bike_control/bluetooth/connection.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prop/prop.dart';

/// The wire trace must be recorded from the moment [Connection.startLogCapture]
/// runs, with the beta entitlement checked only when the trace is exported.
///
/// The regression this guards: the beta gate used to sit at record time, but
/// the entitlement stays unresolved until IAP/Supabase finish initialising —
/// minutes into a session on a cold start. A tester's bundle then contained no
/// `IN>`/`OUT<`/`trainer<`/`trainer>` lines for exactly the connect, handshake
/// and first-ride window it was submitted to show.
void main() {
  tearDown(() => Logger.onTrace = null);

  test('trace recorded before the beta entitlement resolves is exported once it does', () {
    final connection = Connection();
    var beta = false;
    connection.debugIsBetaTester = () => beta;
    connection.startLogCapture();

    Logger.trace(() => 'trainer< ftms 054a00');
    expect(connection.lastTraceEntries, isEmpty,
        reason: 'nothing may be exported while the user does not read as beta');

    beta = true;
    Logger.trace(() => 'trainer> 00002ad9 800501');

    expect(
      connection.lastTraceEntries.map((e) => e.entry),
      ['trainer< ftms 054a00', 'trainer> 00002ad9 800501'],
      reason: 'the pre-entitlement history must be part of the export',
    );
  });

  test('the wire trace of a non-beta user is never exported', () {
    final connection = Connection();
    connection.debugIsBetaTester = () => false;
    connection.startLogCapture();

    Logger.trace(() => 'OUT< 0102');

    expect(connection.lastTraceEntries, isEmpty);
  });
}
