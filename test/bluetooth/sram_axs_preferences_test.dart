import 'package:bike_control/bluetooth/devices/sram/sram_axs.dart';
import 'package:bike_control/utils/actions/base_actions.dart';
import 'package:bike_control/utils/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:universal_ble/universal_ble.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    core.settings.prefs = await SharedPreferences.getInstance();
    core.actionHandler = StubActions();
  });

  testWidgets('the setup action is shown on the main device card', (tester) async {
    final device = SramAxs(BleDevice(deviceId: 'dev1', name: 'SRAM 42'));
    await tester.pumpWidget(
      ShadcnApp(
        home: Scaffold(
          child: Builder(
            builder: (c) => Column(children: device.showAdditionalInformation(c)),
          ),
        ),
      ),
    );
    // The panel lives on the main card now (showAdditionalInformation), not a
    // separate preferences view.
    expect(find.textContaining('Set up SRAM control'), findsOneWidget);
    expect(device.buildPreferences(tester.element(find.byType(Scaffold))), isNull);
  });

  testWidgets('tapping setup opens the interactive authorize-gesture dialog', (tester) async {
    final device = SramAxs(BleDevice(deviceId: 'dev1', name: 'SRAM 42'));
    await tester.pumpWidget(
      ShadcnApp(
        home: Scaffold(
          child: Builder(
            builder: (c) => Column(children: device.showAdditionalInformation(c)),
          ),
        ),
      ),
    );

    await tester.tap(find.textContaining('Set up SRAM control'));
    await tester.pumpAndSettle();

    // The dialog guides the press-and-hold authorize gesture instead of failing
    // silently to the console.
    expect(find.textContaining('Press and hold the AXS button'), findsOneWidget);
    // A Continue affordance is present (the button; the word also appears in the body copy).
    expect(find.widgetWithText(PrimaryButton, 'Continue'), findsOneWidget);
  });
}
