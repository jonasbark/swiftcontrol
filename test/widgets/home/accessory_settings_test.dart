import 'package:bike_control/bluetooth/devices/wahoo/wahoo_kickr_headwind.dart';
import 'package:bike_control/gen/l10n.dart';
import 'package:bike_control/pages/controller_settings.dart';
import 'package:bike_control/utils/actions/base_actions.dart';
import 'package:bike_control/utils/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:universal_ble/universal_ble.dart';

/// The settings page an accessory card opens.
///
/// Its reason to exist for an accessory is the forget action: that is the only
/// route onto the ignore list, and therefore the only way to get rid of a
/// Headwind that belongs to the neighbour rather than the rider.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // The page's Pro badge reaches IAPManager, which reaches Supabase.instance;
  // give it an offline dummy instance (no session, so no request is made).
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'http://127.0.0.1:9',
      anonKey: 'accessory-settings-test-anon-key',
      debug: false,
      authOptions: const FlutterAuthClientOptions(
        localStorage: EmptyLocalStorage(),
        detectSessionInUri: false,
        autoRefreshToken: false,
      ),
    );
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    core.settings.prefs = await SharedPreferences.getInstance();
    core.actionHandler = StubActions();
    await AppLocalizations.load(const Locale('en'));
  });

  Future<void> pumpSettings(WidgetTester tester, WahooKickrHeadwind device) async {
    await tester.pumpWidget(
      ShadcnApp(
        localizationsDelegates: [
          ...ShadcnLocalizations.localizationsDelegates,
          AppLocalizations.delegate,
        ],
        supportedLocales: const [Locale('en')],
        home: ControllerSettingsPage(device: device),
      ),
    );
    // Not pumpAndSettle: a disconnected device's StatusIcon spins forever.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  WahooKickrHeadwind headwind() => WahooKickrHeadwind(BleDevice(deviceId: 'hw-1', name: 'HEADWIND F123'));

  testWidgets('offers the forget action that puts the accessory on the ignore list', (tester) async {
    await pumpSettings(tester, headwind());

    expect(find.text(AppLocalizations.current.disconnectAndForget), findsOneWidget);
  });

  testWidgets('is titled for a device, not a controller', (tester) async {
    await pumpSettings(tester, headwind());

    expect(find.text(AppLocalizations.current.deviceSettings), findsOneWidget);
    expect(find.text(AppLocalizations.current.controllerSettings), findsNothing);
  });

  // A fan has no buttons, so a mapping table would be an empty promise.
  testWidgets('drops the button-mapping section for an accessory', (tester) async {
    await pumpSettings(tester, headwind());

    expect(find.text(AppLocalizations.current.buttonMapping), findsNothing);
  });
}
