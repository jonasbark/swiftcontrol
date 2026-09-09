// Task 14: the app card's chain-card and onboarding entry points into the
// network troubleshooter both gate on the same pure predicate. These tests
// pin down appCardOffersTroubleshooting itself, independent of the widgets
// that read it.
//
// The signals grid used to have its own mount + gating predicate here
// (`signalsGridHasContent`) — removed per direct author feedback ("the
// sensor tiles suddenly landed on the front page - don't put them there").
// `LiveMetricsSection` now only ever mounts on a trainer's own
// `ProxyDeviceDetailsPage` — see that page's own test file — so the one test
// below proves Home renders none of it even in a scenario the deleted
// predicate used to treat as "show the grid".
import 'package:bike_control/bluetooth/devices/proxy/proxy_device.dart';
import 'package:bike_control/gen/l10n.dart';
import 'package:bike_control/main.dart' show screenshotMode;
import 'package:bike_control/pages/home/chain_state.dart';
import 'package:bike_control/pages/home/home_page.dart';
import 'package:bike_control/pages/proxy_device_details/metric_card.dart';
import 'package:bike_control/utils/core.dart';
import 'package:bike_control/utils/keymap/apps/my_whoosh.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:universal_ble/universal_ble.dart';

import '../../widget_snapshot.dart';

ChainLink _appLink({required bool appConnected}) => ChainLink(
  key: ChainLinkKey.app,
  id: 'app',
  status: LinkStatus.attention,
  title: 'MyWhoosh',
  steps: [
    SetupStep(id: SetupStepId.appSelected, done: true),
    SetupStep(id: SetupStepId.appConnectionMethod, done: true),
    SetupStep(id: SetupStepId.appConnected, done: appConnected),
  ],
);

Future<void> main() async {
  await ensureSnapshotHarness();

  setUp(() {
    core.settings.setTrainerApp(MyWhoosh());
    core.settings.setObpMdnsEnabled(true);
    core.obpMdnsEmulator.isStarted.value = true;
  });

  tearDown(() {
    core.obpMdnsEmulator.isStarted.value = false;
    core.settings.setObpMdnsEnabled(false);
    core.connection.devices.clear();
  });

  group('appCardOffersTroubleshooting', () {
    testWidgets('true once the app link is waiting to connect, mDNS is enabled and the emulator is up', (tester) async {
      expect(appCardOffersTroubleshooting(_appLink(appConnected: false)), isTrue);
    });

    testWidgets('false once the app has actually connected', (tester) async {
      expect(appCardOffersTroubleshooting(_appLink(appConnected: true)), isFalse);
    });

    testWidgets('false for a link that is not the app link', (tester) async {
      final link = ChainLink(
        key: ChainLinkKey.trainer,
        id: 'trainer',
        status: LinkStatus.attention,
        title: 'Trainer',
        steps: [SetupStep(id: SetupStepId.appConnected, done: false)],
      );
      expect(appCardOffersTroubleshooting(link), isFalse);
    });

    testWidgets('false when Network mDNS is disabled', (tester) async {
      core.settings.setObpMdnsEnabled(false);
      expect(appCardOffersTroubleshooting(_appLink(appConnected: false)), isFalse);
    });

    testWidgets('false when the mDNS emulator has not started', (tester) async {
      core.obpMdnsEmulator.isStarted.value = false;
      expect(appCardOffersTroubleshooting(_appLink(appConnected: false)), isFalse);
    });
  });

  testWidgets('a bridged trainer no longer makes Home render the signals grid', (tester) async {
    // Deliberately off: `ensureSnapshotHarness` leaves this on, and the grid
    // used to be suppressed under it regardless of the (now-deleted) gate —
    // proving absence there would not prove the mount itself is gone.
    final wasScreenshotMode = screenshotMode;
    screenshotMode = false;
    addTearDown(() => screenshotMode = wasScreenshotMode);

    // A bridged trainer used to be one of `signalsGridHasContent`'s two
    // independent "show the grid" triggers — the strongest case to prove it
    // no longer has any effect at all.
    final trainer = ProxyDevice(BleDevice(deviceId: 'kickr-bridged-home', name: 'Wahoo KICKR'))
      ..debugSetTrainerAppConnected(true);
    core.connection.devices.add(trainer);

    await tester.pumpWidget(
      ShadcnApp(
        localizationsDelegates: [
          ...ShadcnLocalizations.localizationsDelegates,
          AppLocalizations.delegate,
        ],
        supportedLocales: const [Locale('en')],
        home: Scaffold(child: HomePage(isMobile: true, onUpdate: () {})),
      ),
    );
    await tester.pump();

    expect(find.byKey(const ValueKey('live-metrics')), findsNothing);
    expect(find.byType(MetricCard), findsNothing);

    // Unmount before the test ends: with `screenshotMode` off, HomePage's own
    // periodic metrics timer is running, and `flutter_test` fails a test that
    // leaves a pending timer behind — `State.dispose()` cancels it.
    await tester.pumpWidget(const SizedBox());
  });
}
