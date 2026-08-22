import 'dart:async';
import 'dart:io';
import 'package:bike_control/bluetooth/devices/openbikecontrol/obp_mdns_backend.dart';
import 'package:bike_control/pages/network_troubleshooting_page.dart';
import 'package:bike_control/gen/l10n.dart';
import 'package:bike_control/main.dart' show OtherLocalizationsDelegate;
import 'package:bike_control/services/network_self_test/network_check.dart';
import 'package:bike_control/services/network_self_test/network_fixes.dart';
import 'package:bike_control/services/network_self_test/network_probe_context.dart';
import 'package:bike_control/services/network_self_test/network_self_test_engine.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:bike_control/widgets/network_test/network_live_test_card.dart';

import '../widget_snapshot.dart';

NetworkProbeContext _ctx() => NetworkProbeContext(
  snapshot: null, snapshotError: null, emulatorStarted: true, trainerAppConnected: false,
  trainerAppConnectedNow: () => false, trainerAppName: 'MyWhoosh', backend: ObpMdnsBackend.platformDefault,
  advertisedHostname: null, platform: 'macos', resolve: (h) async => const [], tcpProbe: (a, p) async {},
  runProcess: (e, a) async => ProcessResult(0, 0, '', ''), queryLog: () => const [], sleep: (d) async {},
  now: () => DateTime(2026, 8, 22), onWatchProgress: (p) {},
);

ProbeSpec _s(NetworkCheckId id, NetworkVerdict v, {List<NetworkFixId> fixes = const [], Map<String, String> detail = const {}}) =>
    ProbeSpec(id: id, timeout: const Duration(seconds: 5), run: (c) async => NetworkCheck(id: id, verdict: v, fixes: fixes, detail: detail));

Future<void> main() async {
  await ensureSnapshotHarness();

  for (final (size, scale) in [
    (const Size(390, 844), 1.0),
    (const Size(360, 780), 1.0),
    (const Size(320, 700), 1.0),
    (const Size(390, 844), 1.3),
    (const Size(360, 780), 1.6),
  ]) {
    testWidgets('overflow sweep ${size.width.toInt()} @${scale}x', (tester) async {
      final errors = <String>[];
      final previous = FlutterError.onError;
      FlutterError.onError = (details) => errors.add(details.exceptionAsString());
      addTearDown(() => FlutterError.onError = previous);

      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(MediaQuery(
        data: MediaQueryData(size: size, textScaler: TextScaler.linear(scale)),
        child: ShadcnApp(
        debugShowCheckedModeBanner: false,
        localizationsDelegates: [
          ...ShadcnLocalizations.localizationsDelegates,
          const OtherLocalizationsDelegate(),
          AppLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.delegate.supportedLocales,
        home: NetworkTroubleshootingPage(
          engineFactory: () => NetworkSelfTestEngine(contextBuilder: _ctx, probes: [
            _s(NetworkCheckId.methodListening, NetworkVerdict.pass, detail: const {'port': '36867'}),
            _s(NetworkCheckId.localNetworkPermission, NetworkVerdict.fail,
                fixes: [NetworkFixId.openLocalNetworkSettings], detail: const {'state': 'denied'}),
            _s(NetworkCheckId.resolveOwnHostname, NetworkVerdict.fail,
                fixes: [NetworkFixId.useOsResponderForObc, NetworkFixId.useResponderForObc],
                detail: const {'hostname': 'bikecontrol-3f2a.local'}),
            _s(NetworkCheckId.advertisedAddress, NetworkVerdict.pass, detail: const {'address': '192.168.178.197'}),
          ]),
        ),
      )));
      await tester.pump();
      await tester.pump();
      expect(
        errors,
        isEmpty,
        reason: 'the page must lay out at ${size.width.toInt()}px @${scale}x without layout errors',
      );
    });
  }

  for (final (size, scale) in [(const Size(360, 780), 1.0), (const Size(390, 844), 1.6)]) {
    testWidgets('live test card lays out at ${size.width.toInt()} @${scale}x', (tester) async {
      final errors = <String>[];
      final previous = FlutterError.onError;
      FlutterError.onError = (details) => errors.add(details.exceptionAsString());
      addTearDown(() => FlutterError.onError = previous);

      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(MediaQuery(
        data: MediaQueryData(size: size, textScaler: TextScaler.linear(scale)),
        child: ShadcnApp(
          debugShowCheckedModeBanner: false,
          localizationsDelegates: [
            ...ShadcnLocalizations.localizationsDelegates,
            const OtherLocalizationsDelegate(),
            AppLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.delegate.supportedLocales,
          home: const Scaffold(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: NetworkLiveTestCard(
                appName: 'MyWhoosh',
                watch: WatchProgress(
                  browsed: true, resolved: true, addressAsks: 0, connected: false,
                  remaining: Duration(seconds: 48), window: Duration(seconds: 60),
                ),
              ),
            ),
          ),
        ),
      ));
      // The spinner never stops; settle would hang.
      await tester.pump(const Duration(milliseconds: 100));

      expect(errors, isEmpty, reason: 'the live test card must lay out at phone width');
    });
  }
}
