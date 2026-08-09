import 'package:bike_control/bluetooth/devices/sram/sram_axs.dart';
import 'package:bike_control/gen/l10n.dart';
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

  // The panel reads localized strings via context.i18n, so the tree needs the
  // AppLocalizations delegate (mirrors how main.dart wires ShadcnApp).
  Widget wrap(SramAxs device) => ShadcnApp(
        locale: const Locale('en'),
        localizationsDelegates: [
          ...ShadcnLocalizations.localizationsDelegates,
          AppLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.delegate.supportedLocales,
        home: Scaffold(
          child: Builder(
            builder: (c) => Column(children: device.showAdditionalInformation(c)),
          ),
        ),
      );

  testWidgets('the setup action is shown on the main device card', (tester) async {
    final device = SramAxs(BleDevice(deviceId: 'dev1', name: 'SRAM 42'));
    await tester.pumpWidget(wrap(device));

    // The panel lives on the main card now (showAdditionalInformation), not a
    // separate preferences view.
    expect(find.textContaining('Set up SRAM control'), findsOneWidget);
    expect(device.buildPreferences(tester.element(find.byType(Scaffold))), isNull);
  });

  testWidgets('tapping setup opens the guided confirm dialog', (tester) async {
    final device = SramAxs(BleDevice(deviceId: 'dev1', name: 'SRAM 42'));
    await tester.pumpWidget(wrap(device));

    await tester.tap(find.textContaining('Set up SRAM control'));
    await tester.pumpAndSettle();

    // The guided dialog opens with a confirm step (it tries first and only asks
    // to press-and-hold the AXS button if a fresh bond turns out to be needed).
    expect(find.textContaining('so the paddles send button presses instead'), findsOneWidget);
    expect(find.widgetWithText(PrimaryButton, 'Continue'), findsOneWidget);
  });

  testWidgets('the guided sheet is width-capped and centred on wide displays', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final device = SramAxs(BleDevice(deviceId: 'dev1', name: 'SRAM 42'));
    await tester.pumpWidget(wrap(device));

    await tester.tap(find.textContaining('Set up SRAM control'));
    await tester.pumpAndSettle();

    // On a 1440px-wide window the sheet body must not stretch: it's capped at
    // 480 by the ConstrainedBox and centred, not spread across the full width.
    final capped = find.byWidgetPredicate(
      (w) => w is ConstrainedBox && w.constraints.maxWidth == 480,
    );
    expect(capped, findsOneWidget);
    expect(tester.getSize(capped).width, lessThanOrEqualTo(480));
    expect(tester.getCenter(capped).dx, closeTo(720, 1)); // centred in 1440px
  });
}
