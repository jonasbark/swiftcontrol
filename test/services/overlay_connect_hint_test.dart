import 'package:bike_control/bluetooth/devices/proxy/proxy_device.dart';
import 'package:bike_control/bluetooth/messages/notification.dart';
import 'package:bike_control/gen/l10n.dart';
import 'package:bike_control/pages/proxy_device_details.dart';
import 'package:bike_control/pages/proxy_device_details/overlay_settings_section.dart';
import 'package:bike_control/utils/actions/base_actions.dart';
import 'package:bike_control/utils/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prop/emulators/definitions/fitness_bike_definition.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:universal_ble/universal_ble.dart';

/// The one-time "enable the gear overlay" hint fired when a trainer app first
/// connects to the virtual trainer (OverlayConnectHint via ProxyDevice).
///
/// The connect is driven through [ProxyDevice.debugSetTrainerAppConnected]
/// (the device-level wrapper the hint listens on) rather than the emulator's
/// own isConnected: flipping the latter runs prop's connect machinery, whose
/// real BLE/transport futures wedge the widget-test fake clock. The
/// emulator→wrapper mirror itself is covered by
/// proxy_device_smart_trainer_test.dart. Stream assertions use plain test() +
/// pumpEventQueue like connection_alert_wiring_test.dart — testWidgets'
/// FakeAsync teardown hangs on the notification delivery's real async.
Future<void> main() async {
  await AppLocalizations.load(const Locale('en'));

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    core.settings.prefs = await SharedPreferences.getInstance();
    core.actionHandler = StubActions();
  });

  /// A trainer with an active Virtual Shifting session (fitnessBike attached).
  ProxyDevice makeVsDevice() {
    final device = ProxyDevice(
      BleDevice(
        deviceId: 'kickr',
        name: 'KICKR CORE',
        services: const [FitnessBikeDefinition.FITNESS_MACHINE_SERVICE_UUID],
      ),
    )..services = [BleService(FitnessBikeDefinition.FITNESS_MACHINE_SERVICE_UUID, [])];
    device.debugAttachFitnessBike(
      FitnessBikeDefinition(
        connectedDevice: device.scanResult,
        connectedDeviceServices: device.services!,
        data: ValueNotifier(''),
      ),
    );
    return device;
  }

  /// Collects the overlay hints (identified by their button title) emitted on
  /// the notification stream while [act] runs.
  Future<List<AlertNotification>> collectHints(void Function() act) async {
    final hints = <AlertNotification>[];
    final sub = core.connection.actionStream.listen((n) {
      if (n is AlertNotification && n.buttonTitle == AppLocalizations.current.overlayConnectHintButton) {
        hints.add(n);
      }
    });
    act();
    await pumpEventQueue();
    await sub.cancel();
    return hints;
  }

  test('first client connect with overlay disabled fires the one-time hint', () async {
    final device = makeVsDevice();

    final hints = await collectHints(() => device.debugSetTrainerAppConnected(true));

    expect(hints, hasLength(1));
    expect(
      hints.single.alertMessage,
      AppLocalizations.current.overlayConnectHint(AppLocalizations.current.yourTrainerApp),
    );
    // The button deep-links to the trainer detail page (the deep-link target
    // is exercised by the revealOverlaySection widget test below).
    expect(hints.single.onTap, isNotNull);
    // The one-time flag is persisted the moment the hint fires.
    expect(core.settings.getOverlayConnectHintShown(), isTrue);
  });

  test('does not fire again after it was shown once', () async {
    final device = makeVsDevice();

    final first = await collectHints(() => device.debugSetTrainerAppConnected(true));
    expect(first, hasLength(1));

    // Trainer app disconnects and reconnects — the hint stays dismissed.
    final second = await collectHints(() {
      device.debugSetTrainerAppConnected(false);
      device.debugSetTrainerAppConnected(true);
    });
    expect(second, isEmpty);
  });

  test('does not fire when the overlay is already enabled', () async {
    await core.settings.setOverlayEnabled(true);
    final device = makeVsDevice();

    final hints = await collectHints(() => device.debugSetTrainerAppConnected(true));

    expect(hints, isEmpty);
    // The one-time flag was not burned: if the rider later disables the
    // overlay, the hint is still available.
    expect(core.settings.getOverlayConnectHintShown(), isFalse);
  });

  test('does not fire without an active Virtual Shifting session', () async {
    // No fitnessBike attached → BikeControl computes no gear → nothing for the
    // overlay to show, so the hint would only confuse.
    final device = ProxyDevice(
      BleDevice(
        deviceId: 'kickr',
        name: 'KICKR CORE',
        services: const [FitnessBikeDefinition.FITNESS_MACHINE_SERVICE_UUID],
      ),
    );

    final hints = await collectHints(() => device.debugSetTrainerAppConnected(true));

    expect(hints, isEmpty);
    expect(core.settings.getOverlayConnectHintShown(), isFalse);
  });

  testWidgets('revealOverlaySection lands the rider on the Overlay section', (tester) async {
    final device = makeVsDevice();

    await tester.pumpWidget(
      ShadcnApp(
        localizationsDelegates: const [AppLocalizations.delegate],
        supportedLocales: AppLocalizations.delegate.supportedLocales,
        home: ProxyDeviceDetailsPage(device: device, revealOverlaySection: true),
      ),
    );
    await tester.pump();
    // Let the post-frame ensureVisible scroll animation run out.
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byType(OverlaySettingsSection), findsOneWidget);
    expect(find.text(AppLocalizations.current.overlayEnabled), findsOneWidget);
  });
}
