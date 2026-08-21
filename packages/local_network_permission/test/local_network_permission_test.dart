import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_network_permission/local_network_permission.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final calls = <MethodCall>[];
  late Object? reply;

  void mockNative(Object? Function(MethodCall call) handler) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      LocalNetworkPermission.channel,
      (call) async {
        calls.add(call);
        return handler(call);
      },
    );
  }

  setUp(() {
    calls.clear();
    reply = 'granted';
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    mockNative((_) => reply);
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      LocalNetworkPermission.channel,
      null,
    );
  });

  group('check', () {
    test('maps the native outcome strings', () async {
      reply = 'granted';
      expect(await LocalNetworkPermission.check(), LocalNetworkStatus.granted);
      reply = 'denied';
      expect(await LocalNetworkPermission.check(), LocalNetworkStatus.denied);
      reply = 'unknown';
      expect(await LocalNetworkPermission.check(), LocalNetworkStatus.unknown);
    });

    test('an unrecognised or absent outcome is unknown, never denied', () async {
      reply = 'something-new';
      expect(await LocalNetworkPermission.check(), LocalNetworkStatus.unknown);
      reply = null;
      expect(await LocalNetworkPermission.check(), LocalNetworkStatus.unknown);
    });

    test('forwards the timeout in milliseconds', () async {
      await LocalNetworkPermission.check(timeout: const Duration(milliseconds: 1500));
      expect(calls.single.method, 'check');
      expect(calls.single.arguments, {'timeoutMs': 1500});
    });

    test('is unknown without touching the channel off iOS/macOS', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      expect(await LocalNetworkPermission.check(), LocalNetworkStatus.unknown);
      expect(calls, isEmpty);
    });

    test('is unknown when the plugin is missing, rather than throwing', () async {
      mockNative((call) => throw MissingPluginException('no ${call.method}'));
      expect(await LocalNetworkPermission.check(), LocalNetworkStatus.unknown);
    });

    test('gives up on a wedged native probe instead of hanging', () async {
      mockNative((_) => Completer<String>().future);
      expect(
        await LocalNetworkPermission.check(timeout: const Duration(milliseconds: 20)),
        LocalNetworkStatus.unknown,
      );
    });

    test('surfaces a native probe failure', () async {
      mockNative((_) => throw PlatformException(code: 'probe_unavailable'));
      expect(LocalNetworkPermission.check(), throwsA(isA<PlatformException>()));
    });
  });

  group('openSettings', () {
    test('invokes the native opener on macOS', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      await LocalNetworkPermission.openSettings();
      expect(calls.single.method, 'openSettings');
    });

    test('is a no-op off iOS/macOS', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      await LocalNetworkPermission.openSettings();
      expect(calls, isEmpty);
    });

    test('tolerates a missing plugin', () async {
      mockNative((call) => throw MissingPluginException('no ${call.method}'));
      await expectLater(LocalNetworkPermission.openSettings(), completes);
    });
  });
}
