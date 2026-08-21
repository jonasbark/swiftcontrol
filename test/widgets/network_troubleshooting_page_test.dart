import 'dart:async';
import 'dart:io';

import 'package:bike_control/bluetooth/devices/openbikecontrol/obp_mdns_backend.dart';
import 'package:bike_control/gen/l10n.dart';
import 'package:bike_control/main.dart' show OtherLocalizationsDelegate, navigatorKey;
import 'package:bike_control/pages/network_troubleshooting_page.dart';
import 'package:bike_control/services/network_self_test/network_check.dart';
import 'package:bike_control/services/network_self_test/network_probe_context.dart';
import 'package:bike_control/services/network_self_test/network_self_test_engine.dart';
import 'package:bike_control/utils/core.dart';
import 'package:bike_control/widgets/network_check_row.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../widget_snapshot.dart';

/// Pumps [child] inside a real [ShadcnApp], wired to the app's global
/// [navigatorKey] — `buildToast()` (used by the copy-results button) reads
/// `navigatorKey.currentContext`, so the toast test needs the same key the
/// page's toast helper reaches for.
Future<void> _pump(WidgetTester tester, Widget child) {
  return tester.pumpWidget(
    ShadcnApp(
      debugShowCheckedModeBanner: false,
      navigatorKey: navigatorKey,
      localizationsDelegates: [
        ...ShadcnLocalizations.localizationsDelegates,
        const OtherLocalizationsDelegate(),
        AppLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.delegate.supportedLocales,
      home: child,
    ),
  );
}

/// A context with no-op seams; the scripted [ProbeSpec]s below never read it.
NetworkProbeContext _ctx() => NetworkProbeContext(
  snapshot: null,
  snapshotError: null,
  emulatorStarted: true,
  trainerAppConnected: false,
  trainerAppConnectedNow: () => false,
  trainerAppName: 'MyWhoosh',
  backend: ObpMdnsBackend.platformDefault,
  advertisedHostname: null,
  platform: 'macos',
  resolve: (host) async => const [],
  tcpProbe: (address, port) async {},
  runProcess: (executable, arguments) async => ProcessResult(0, 0, '', ''),
  queryLog: () => const [],
  sleep: (d) async {},
  now: () => DateTime(2026, 8, 21),
  onWatchProgress: (progress) {},
);

AppLocalizations _l10n(WidgetTester tester) => AppLocalizations.of(tester.element(find.byType(NetworkTroubleshootingPage)));

Future<void> main() async {
  await ensureSnapshotHarness();

  tearDown(() {
    // Task 12's brief-mandated reset: a test that flips this must not leak
    // "already connected" into whichever widget test file runs next in the
    // same process.
    core.obpMdnsEmulator.isConnected.value = false;
  });

  testWidgets('auto-start renders a running row, then result rows, in order', (tester) async {
    final c1 = Completer<NetworkCheck>();
    final c2 = Completer<NetworkCheck>();
    final probes = [
      ProbeSpec(id: NetworkCheckId.methodListening, timeout: const Duration(seconds: 5), run: (ctx) => c1.future),
      ProbeSpec(id: NetworkCheckId.advertisedAddress, timeout: const Duration(seconds: 5), run: (ctx) => c2.future),
    ];
    final engine = NetworkSelfTestEngine(contextBuilder: _ctx, probes: probes);

    await _pump(tester, NetworkTroubleshootingPage(engineFactory: () => engine));
    await tester.pump();

    // First probe in flight: its running placeholder row shows, nothing
    // completed yet.
    expect(find.byKey(const ValueKey('check-methodListening-running')), findsOneWidget);
    expect(find.byKey(const ValueKey('check-methodListening')), findsNothing);

    c1.complete(const NetworkCheck(id: NetworkCheckId.methodListening, verdict: NetworkVerdict.pass));
    await tester.pump();
    await tester.pump();

    // The first check is now a completed row, ABOVE the second probe's own
    // running placeholder.
    final completedFirst = tester.getRect(find.byKey(const ValueKey('check-methodListening')));
    expect(find.byKey(const ValueKey('check-advertisedAddress-running')), findsOneWidget);
    final runningSecond = tester.getRect(find.byKey(const ValueKey('check-advertisedAddress-running')));
    expect(completedFirst.top, lessThan(runningSecond.top));

    c2.complete(const NetworkCheck(id: NetworkCheckId.advertisedAddress, verdict: NetworkVerdict.pass));
    await tester.pump();
    await tester.pump();

    // Both checks are now completed rows, in the order they ran, and the
    // header has switched from "running" to the result view.
    expect(find.byKey(const ValueKey('check-methodListening')), findsOneWidget);
    expect(find.byKey(const ValueKey('check-advertisedAddress')), findsOneWidget);
    expect(find.byKey(const ValueKey('network-run-again')), findsOneWidget);
    expect(find.byKey(const ValueKey('network-cancel')), findsNothing);
  });

  testWidgets('shows the refusal card instead of auto-starting when already connected', (tester) async {
    core.obpMdnsEmulator.isConnected.value = true;

    var built = false;
    final probes = [
      ProbeSpec(
        id: NetworkCheckId.methodListening,
        timeout: const Duration(seconds: 1),
        run: (ctx) async => const NetworkCheck(id: NetworkCheckId.methodListening, verdict: NetworkVerdict.pass),
      ),
    ];
    await _pump(
      tester,
      NetworkTroubleshootingPage(
        engineFactory: () {
          built = true;
          return NetworkSelfTestEngine(contextBuilder: _ctx, probes: probes);
        },
      ),
    );
    await tester.pump();

    expect(built, isFalse, reason: 'a connected trainer app must not auto-start a run');
    expect(find.byType(NetworkCheckRow), findsNothing);
    expect(find.text(_l10n(tester).networkTroubleshootRun), findsOneWidget);
  });

  testWidgets('recommended-fix button appears when a check failed', (tester) async {
    final probes = [
      ProbeSpec(
        id: NetworkCheckId.resolveOwnHostname,
        timeout: const Duration(seconds: 1),
        run: (ctx) async => const NetworkCheck(
          id: NetworkCheckId.resolveOwnHostname,
          verdict: NetworkVerdict.fail,
          fixes: [NetworkFixId.useOsResponderForObc],
        ),
      ),
    ];
    final engine = NetworkSelfTestEngine(contextBuilder: _ctx, probes: probes);

    await _pump(tester, NetworkTroubleshootingPage(engineFactory: () => engine));
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const ValueKey('network-recommended-fix')), findsOneWidget);
  });

  testWidgets('copy button copies the bundle and toasts, without throwing', (tester) async {
    final probes = [
      ProbeSpec(
        id: NetworkCheckId.methodListening,
        timeout: const Duration(seconds: 1),
        run: (ctx) async => const NetworkCheck(id: NetworkCheckId.methodListening, verdict: NetworkVerdict.pass),
      ),
    ];
    final engine = NetworkSelfTestEngine(contextBuilder: _ctx, probes: probes);

    await _pump(tester, NetworkTroubleshootingPage(engineFactory: () => engine));
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const ValueKey('network-copy')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('network-copy')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text(_l10n(tester).networkTroubleshootResultsCopied), findsOneWidget);
  });

  testWidgets('cancel mid-run yields a result with completed == false', (tester) async {
    final c1 = Completer<NetworkCheck>();
    final probes = [
      ProbeSpec(id: NetworkCheckId.methodListening, timeout: const Duration(seconds: 5), run: (ctx) => c1.future),
      ProbeSpec(
        id: NetworkCheckId.advertisedAddress,
        timeout: const Duration(seconds: 1),
        run: (ctx) async => const NetworkCheck(id: NetworkCheckId.advertisedAddress, verdict: NetworkVerdict.pass),
      ),
    ];
    final engine = NetworkSelfTestEngine(contextBuilder: _ctx, probes: probes);

    await _pump(tester, NetworkTroubleshootingPage(engineFactory: () => engine));
    await tester.pump();

    expect(find.byKey(const ValueKey('network-cancel')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('network-cancel')));
    await tester.pump();

    // The first probe was already in flight when cancel() was tapped, so it
    // still finishes on its own — cancel() only stops the ones after it.
    c1.complete(const NetworkCheck(id: NetworkCheckId.methodListening, verdict: NetworkVerdict.pass));
    await tester.pump();
    await tester.pump();

    expect(engine.state.value.result, isNotNull);
    expect(engine.state.value.result!.completed, isFalse);
  });
}
