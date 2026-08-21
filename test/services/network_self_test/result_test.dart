import 'dart:convert';

import 'package:bike_control/services/network_self_test/network_check.dart';
import 'package:bike_control/services/network_self_test/network_self_test_result.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('overall verdict severity ordering: fail > unknown > warn > pass; skipped ignored', () {
    expect(
      overallVerdict(const [
        NetworkCheck(id: NetworkCheckId.vpn, verdict: NetworkVerdict.warn),
        NetworkCheck(id: NetworkCheckId.backend, verdict: NetworkVerdict.fail),
        NetworkCheck(id: NetworkCheckId.methodListening, verdict: NetworkVerdict.unknown),
      ]),
      NetworkVerdict.fail,
    );

    expect(
      overallVerdict(const [
        NetworkCheck(id: NetworkCheckId.vpn, verdict: NetworkVerdict.warn),
        NetworkCheck(id: NetworkCheckId.methodListening, verdict: NetworkVerdict.unknown),
      ]),
      NetworkVerdict.unknown,
    );

    expect(
      overallVerdict(const [
        NetworkCheck(id: NetworkCheckId.vpn, verdict: NetworkVerdict.warn),
        NetworkCheck(id: NetworkCheckId.methodListening, verdict: NetworkVerdict.pass),
      ]),
      NetworkVerdict.warn,
    );

    // skipped rows are ignored entirely; empty / all-skipped -> pass.
    expect(overallVerdict(const []), NetworkVerdict.pass);
    expect(
      overallVerdict(const [
        NetworkCheck(id: NetworkCheckId.vpn, verdict: NetworkVerdict.skipped),
        NetworkCheck(id: NetworkCheckId.backend, verdict: NetworkVerdict.skipped),
      ]),
      NetworkVerdict.pass,
    );
    expect(
      overallVerdict(const [
        NetworkCheck(id: NetworkCheckId.vpn, verdict: NetworkVerdict.skipped),
        NetworkCheck(id: NetworkCheckId.backend, verdict: NetworkVerdict.fail),
      ]),
      NetworkVerdict.fail,
    );
  });

  test('json round trip preserves detail maps and fixes', () {
    final result = NetworkSelfTestResult(
      at: DateTime(2026, 8, 21, 10, 30),
      platform: 'macos',
      obcBackend: 'flutterNsd',
      hostname: 'jonas-mbp.local',
      checks: const [
        NetworkCheck(
          id: NetworkCheckId.resolveOwnHostname,
          verdict: NetworkVerdict.fail,
          detail: {'latencyMs': '3000', 'error': 'timeout'},
          fixes: [NetworkFixId.switchToLocal, NetworkFixId.sendToSupport],
        ),
      ],
      completed: true,
    );

    final back = NetworkSelfTestResult.fromJson(jsonDecode(result.toJsonString()) as Map<String, dynamic>);

    expect(back.at, result.at);
    expect(back.platform, 'macos');
    expect(back.obcBackend, 'flutterNsd');
    expect(back.hostname, 'jonas-mbp.local');
    expect(back.completed, isTrue);
    expect(back.checks.single.id, NetworkCheckId.resolveOwnHostname);
    expect(back.checks.single.verdict, NetworkVerdict.fail);
    expect(back.checks.single.detail, {'latencyMs': '3000', 'error': 'timeout'});
    expect(back.checks.single.fixes, [NetworkFixId.switchToLocal, NetworkFixId.sendToSupport]);
  });

  test('fromJson drops unknown check ids and unknown fix ids without throwing', () {
    final json = {
      'at': DateTime(2026, 8, 21).toIso8601String(),
      'platform': 'windows',
      'obcBackend': 'osResponder',
      'checks': [
        {
          'id': 'fromTheFuture',
          'verdict': 'fail',
          'detail': <String, dynamic>{},
          'fixes': <String>[],
        },
        {
          'id': 'vpn',
          'verdict': 'warn',
          'detail': <String, dynamic>{},
          'fixes': ['teleport', 'switchToLocal'],
        },
      ],
      'completed': true,
    };

    final result = NetworkSelfTestResult.fromJson(json);

    expect(result.checks.length, 1);
    expect(result.checks.single.id, NetworkCheckId.vpn);
    expect(result.checks.single.fixes, [NetworkFixId.switchToLocal]);
  });

  test('tryParse returns null for null input', () {
    expect(NetworkSelfTestResult.tryParse(null), isNull);
  });

  test('tryParse returns null for garbage input', () {
    expect(NetworkSelfTestResult.tryParse('not json {{{'), isNull);
  });

  test('toBundleString renders header and one line per non-skipped check', () {
    final result = NetworkSelfTestResult(
      at: DateTime(2026, 8, 21),
      platform: 'windows',
      obcBackend: 'osResponder',
      hostname: 'DESKTOP-JONAS',
      checks: const [
        NetworkCheck(
          id: NetworkCheckId.resolveOwnHostname,
          verdict: NetworkVerdict.fail,
          detail: {'latencyMs': '3000'},
        ),
        NetworkCheck(id: NetworkCheckId.vpn, verdict: NetworkVerdict.pass),
        NetworkCheck(id: NetworkCheckId.multicastLock, verdict: NetworkVerdict.skipped),
      ],
      completed: true,
    );

    final bundle = result.toBundleString();
    expect(bundle, contains('NETWORK FAIL,2026-08-21,windows,osResponder,host=DESKTOP-JONAS'));
    expect(bundle, contains('resolveOwnHostname=fail latencyMs=3000'));
    expect(bundle, contains('vpn=pass'));
    expect(bundle, isNot(contains('multicastLock')));
  });
}
