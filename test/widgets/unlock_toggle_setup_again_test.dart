import 'package:bike_control/bluetooth/devices/bluetooth_device.dart';
import 'package:bike_control/bluetooth/devices/zwift/constants.dart';
import 'package:bike_control/bluetooth/devices/zwift/zwift_clickv2_left_side.dart';
import 'package:bike_control/gen/l10n.dart';
import 'package:bike_control/pages/click_v2_onboarding.dart';
import 'package:bike_control/utils/actions/base_actions.dart';
import 'package:bike_control/utils/core.dart';
import 'package:bike_control/widgets/unlock_toggle.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:universal_ble/universal_ble.dart';
import 'dart:typed_data';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ZwiftClickV2LeftSide device;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    core.actionHandler = StubActions();
    core.settings.prefs = await SharedPreferences.getInstance();
    await AppLocalizations.load(const Locale('en'));

    device = BluetoothDevice.fromScanResult(
      BleDevice(
        deviceId: 'click-left',
        name: 'Zwift Click',
        manufacturerDataList: [
          ManufacturerData(
            ZwiftConstants.ZWIFT_MANUFACTURER_ID,
            Uint8List.fromList([ZwiftConstants.CLICK_V2_LEFT_SIDE]),
          ),
        ],
        services: [ZwiftConstants.ZWIFT_CUSTOM_SERVICE_UUID.toLowerCase()],
      ),
    ) as ZwiftClickV2LeftSide;
  });

  testWidgets('offers a way back into the onboarding explainer', (tester) async {
    await tester.pumpWidget(
      ShadcnApp(
        localizationsDelegates: const [AppLocalizations.delegate],
        supportedLocales: const [Locale('en')],
        home: Scaffold(child: UnlockToggle(device: device, children: const [])),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Set up again'), findsOneWidget);

    await tester.tap(find.text('Set up again'));
    await tester.pumpAndSettle();

    expect(find.byType(ClickV2OnboardingPage), findsOneWidget);
  });

  testWidgets('flipping unlock mode on a never-connected device does not throw', (tester) async {
    // A device fresh off a scan result -- never connected -- has services ==
    // null; BluetoothDevice.connect() is what populates it. This is the
    // narrow race the guard in UnlockToggle exists for: isConnected can flip
    // true before that assignment lands.
    expect(device.services, isNull);

    // Start on "Unlock using Zwift" so switching to "Restart" below exercises
    // the ClickLogic.setupHandshake branch (the else arm), not resetTimer.
    await core.settings.setUnlockWithZwift(true);

    await tester.pumpWidget(
      ShadcnApp(
        localizationsDelegates: const [AppLocalizations.delegate],
        supportedLocales: const [Locale('en')],
        home: Scaffold(child: UnlockToggle(device: device, children: const [])),
      ),
    );
    await tester.pumpAndSettle();

    // Open the dropdown via its current (Zwift) value, then pick "Restart".
    await tester.tap(find.text('Unlock using Zwift'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Restart device every minute'));
    await tester.pumpAndSettle();

    // Before the guard, this would have thrown on `services!` with services
    // still null. No exception reaching here is the assertion.
    expect(tester.takeException(), isNull);
  });
}
