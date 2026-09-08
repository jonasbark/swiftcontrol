// Task 14: the app card's chain-card and onboarding entry points into the
// network troubleshooter both gate on the same pure predicate. These tests
// pin down appCardOffersTroubleshooting itself, independent of the widgets
// that read it.
//
// signalsGridHasContent pins down the OTHER pure predicate this page reads
// straight off `core` — whether Home should mount `LiveMetricsSection` at
// all (see the doc comment on the function itself for the two OR'd reasons).
import 'package:bike_control/bluetooth/devices/proxy/proxy_device.dart';
import 'package:bike_control/bluetooth/devices/sensors/ble_heart_rate_device.dart';
import 'package:bike_control/pages/home/chain_state.dart';
import 'package:bike_control/pages/home/home_page.dart';
import 'package:bike_control/services/sensors/fake_sensor_source.dart';
import 'package:bike_control/services/sensors/sensor_quantity.dart';
import 'package:bike_control/utils/core.dart';
import 'package:bike_control/utils/keymap/apps/my_whoosh.dart';
import 'package:flutter_test/flutter_test.dart';
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
    // signalsGridHasContent reads both of these directly; start every test
    // (including the pre-existing appCardOffersTroubleshooting ones, which
    // never touch either) from a known-empty slate.
    core.connection.devices.clear();
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

  group('signalsGridHasContent (gates whether Home mounts LiveMetricsSection)', () {
    testWidgets('nothing at all: no trainer, no sensor anywhere — false', (tester) async {
      expect(signalsGridHasContent(), isFalse);
    });

    testWidgets('a trainer that exists but is not bridged, no sensors: still false', (tester) async {
      // Present, even discovered — just never connected. Mere presence is
      // not what "connected" means for a trainer here; see the doc comment
      // on ProxyDevice.isBridged.
      final trainer = ProxyDevice(BleDevice(deviceId: 'kickr-idle', name: 'Wahoo KICKR'));
      core.connection.devices.add(trainer);

      expect(signalsGridHasContent(), isFalse);
    });

    testWidgets('a bridged trainer, no sensors: true', (tester) async {
      final trainer = ProxyDevice(BleDevice(deviceId: 'kickr-bridged', name: 'Wahoo KICKR'))
        ..debugSetTrainerAppConnected(true);
      core.connection.devices.add(trainer);

      expect(signalsGridHasContent(), isTrue);
    });

    testWidgets(
      'THE CHICKEN-AND-EGG CASE: no trainer, a sensor discovered nearby but nothing registered or '
      'selected yet — true, or the picker would never be reachable',
      (tester) async {
        final nearby = BleHeartRateDevice(BleDevice(deviceId: 'nearby-hr', name: 'TICKR 1234'));
        core.connection.devices.add(nearby);

        expect(signalsGridHasContent(), isTrue);
      },
    );

    testWidgets('no trainer, a source registered with the hub though nothing is selected yet: true', (tester) async {
      final source = FakeSensorSource(id: 'hr-registered', displayName: 'HR6 0050789', provides: {
        SensorQuantity.heartRate,
      });
      core.sensors.register(source);
      addTearDown(() => core.sensors.unregister(source.id));

      expect(signalsGridHasContent(), isTrue);
    });

    testWidgets('no trainer, a quantity already selected though its source has not registered yet: true', (tester) async {
      core.sensors.select(SensorQuantity.cadence, 'ghost-cadence-source');
      addTearDown(() => core.sensors.select(SensorQuantity.cadence, null));

      expect(signalsGridHasContent(), isTrue);
    });
  });
}
