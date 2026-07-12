import 'dart:async';

import 'package:bike_control/bluetooth/devices/wheeltop/wheeltop_eds.dart';
import 'package:bike_control/bluetooth/emulation/emulated_ble_platform.dart';
import 'package:bike_control/bluetooth/emulation/emulated_peripherals.dart';
import 'package:bike_control/bluetooth/messages/notification.dart';
import 'package:bike_control/gen/l10n.dart';
import 'package:bike_control/utils/actions/base_actions.dart';
import 'package:bike_control/utils/core.dart';
import 'package:bike_control/utils/keymap/apps/zwift.dart';
import 'package:flutter_test/flutter_test.dart';

import 'harness/test_env.dart';

/// Auto-connect backoff for devices that limit their attempts (Wheeltop EDS):
/// counting, suppression, cooldown, guidance alert, Retry — through the REAL
/// Connection class; only the BLE platform is fake.
Future<void> main() async {
  final env = await IntegrationEnv.setUp();
  late StubActions stubActions;
  final notifications = <BaseNotification>[];
  late StreamSubscription<BaseNotification> notificationSub;
  Timer? advTimer;

  core.connection.initialize();

  /// Re-emit the advertisement continuously, like a real pod's beacon — the
  /// retry loop is driven by rediscovery, which the fake only produces on
  /// explicit updateScanResult calls.
  void startAdvertising(FakePeripheral peripheral) {
    advTimer?.cancel();
    advTimer = Timer.periodic(
      const Duration(milliseconds: 40),
      (_) => env.ble.updateScanResult(peripheral.scanResult),
    );
  }

  setUp(() async {
    await env.resetState();
    stubActions = StubActions();
    stubActions.supportedApp = Zwift();
    core.actionHandler = stubActions;
    notifications.clear();
    notificationSub = core.connection.actionStream.listen(notifications.add);
  });

  tearDown(() async {
    advTimer?.cancel();
    await notificationSub.cancel();
    await env.resetConnection();
  });

  int connectingCount() => notifications
      .whereType<AlertNotification>()
      .where((n) => n.alertMessage.startsWith('Connecting to:') && n.alertMessage.contains('WHEELTOP EDS TX Left'))
      .length;

  int failedToastCount() => notifications
      .whereType<AlertNotification>()
      .where((n) => n.alertMessage.startsWith('Connection failed:') && n.alertMessage.contains('WHEELTOP EDS TX Left'))
      .length;

  List<AlertNotification> guidanceAlerts() => notifications
      .whereType<AlertNotification>()
      .where((n) => n.alertMessage.contains(AppLocalizations.current.wheeltopClaimedByDerailleurHint))
      .toList();

  test('healthy pod connects and subscribes to the button characteristic', () async {
    final pod = buildWheeltopEdsTxLeft();
    env.ble.addPeripheral(pod);
    await core.connection.performScanning();

    await IntegrationEnv.waitFor(
      () => core.connection.devices.whereType<WheeltopEds>().any((d) => d.isConnected),
      description: 'WheeltopEds to connect',
    );
    await IntegrationEnv.waitFor(
      () => pod.subscriptions.contains(WheeltopEdsConstants.TX_CHARACTERISTIC_UUID.toLowerCase()),
      description: 'subscription to the button characteristic',
    );
    expect(guidanceAlerts(), isEmpty);
  });
}
