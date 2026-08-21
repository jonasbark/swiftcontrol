import 'dart:async';

import 'package:bike_control/services/local_network_access.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_network_permission/local_network_permission.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  var probes = 0;
  late Object? Function() respond;
  late DateTime clock;

  void mockNative(Object? Function() handler) {
    respond = handler;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      LocalNetworkPermission.channel,
      (call) async {
        if (call.method != 'check') return null;
        probes++;
        return respond();
      },
    );
  }

  setUp(() {
    probes = 0;
    clock = DateTime(2026, 8, 20, 12);
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    LocalNetworkAccess.resetForTest();
    LocalNetworkAccess.now = () => clock;
    mockNative(() => 'granted');
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    LocalNetworkAccess.resetForTest();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      LocalNetworkPermission.channel,
      null,
    );
  });

  test('probes once and serves the rest from cache', () async {
    expect(await LocalNetworkAccess.status(), LocalNetworkStatus.granted);
    expect(await LocalNetworkAccess.status(), LocalNetworkStatus.granted);
    expect(probes, 1);
  });

  test('re-probes once the cache goes stale', () async {
    await LocalNetworkAccess.status();
    clock = clock.add(LocalNetworkAccess.cacheDuration - const Duration(seconds: 1));
    await LocalNetworkAccess.status();
    expect(probes, 1, reason: 'still inside the cache window');

    clock = clock.add(const Duration(seconds: 2));
    await LocalNetworkAccess.status();
    expect(probes, 2);
  });

  test('force re-probes even on a fresh cache', () async {
    await LocalNetworkAccess.status();
    await LocalNetworkAccess.status(force: true);
    expect(probes, 2);
  });

  test('invalidate drops the cache', () async {
    await LocalNetworkAccess.status();
    expect(LocalNetworkAccess.cached, LocalNetworkStatus.granted);
    LocalNetworkAccess.invalidate();
    expect(LocalNetworkAccess.cached, isNull);
    await LocalNetworkAccess.status();
    expect(probes, 2);
  });

  test('cached reports nothing once the entry is stale', () async {
    await LocalNetworkAccess.status();
    clock = clock.add(LocalNetworkAccess.cacheDuration);
    expect(LocalNetworkAccess.cached, isNull);
  });

  test('concurrent callers share a single probe', () async {
    // Two overlapping probes would advertise the same Bonjour type twice and
    // could resolve each other, so overlap has to collapse into one.
    final gate = Completer<void>();
    mockNative(() => gate.future.then((_) => 'denied'));

    final first = LocalNetworkAccess.status();
    final second = LocalNetworkAccess.status();
    gate.complete();

    expect(await first, LocalNetworkStatus.denied);
    expect(await second, LocalNetworkStatus.denied);
    expect(probes, 1);
  });

  test('a probe that failed does not wedge later probes', () async {
    mockNative(() => throw PlatformException(code: 'probe_unavailable'));
    expect(await LocalNetworkAccess.status(), LocalNetworkStatus.unknown);

    mockNative(() => 'granted');
    expect(await LocalNetworkAccess.status(force: true), LocalNetworkStatus.granted);
  });

  group('isUsable', () {
    test('blocks only on a positive denial', () async {
      mockNative(() => 'denied');
      expect(await LocalNetworkAccess.isUsable(), isFalse);
    });

    test('fails open when the probe could not tell', () async {
      mockNative(() => 'unknown');
      expect(await LocalNetworkAccess.isUsable(), isTrue);
    });

    test('fails open when the native probe errors out', () async {
      // A broken probe must never lock a working setup out of its trainer app.
      mockNative(() => throw PlatformException(code: 'probe_unavailable'));
      expect(await LocalNetworkAccess.isUsable(), isTrue);
    });

    test('allows a grant', () async {
      expect(await LocalNetworkAccess.isUsable(), isTrue);
    });
  });
}
