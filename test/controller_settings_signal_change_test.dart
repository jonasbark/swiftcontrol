import 'package:bike_control/bluetooth/devices/sram/sram_axs.dart';
import 'package:bike_control/gen/l10n.dart';
import 'package:bike_control/pages/controller_settings.dart';
import 'package:bike_control/utils/actions/base_actions.dart';
import 'package:bike_control/utils/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:universal_ble/universal_ble.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // The page builds CustomizePage, whose IAP wiring reaches Supabase.instance;
  // give it an offline dummy instance (no session, so no network request).
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'http://127.0.0.1:9',
      anonKey: 'controller-settings-test-anon-key',
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
  });

  testWidgets('page rebuilds on signalChange so Restore appears after SRAM setup', (tester) async {
    final device = SramAxs(BleDevice(deviceId: 'dev1', name: 'SRAM 42'));
    // The setup panel gates its Restore branch on isBonded. Persist a session
    // key and run handleServices so the device seeds it — the same path a
    // real (re)connect takes to become bonded.
    await core.settings.setSramKey('dev1', '00112233445566778899aabbccddeeff');
    await device.handleServices(const []);
    await tester.pumpWidget(
      ShadcnApp(
        localizationsDelegates: [
          ...ShadcnLocalizations.localizationsDelegates,
          AppLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.delegate.supportedLocales,
        home: ControllerSettingsPage(device: device),
      ),
    );
    await tester.pump();

    expect(find.textContaining('Set up SRAM control'), findsOneWidget);
    expect(find.textContaining('Restore original shifting'), findsNothing);

    // What setupControl() persists on success…
    await core.settings.setSramBackup('dev1', {});
    await core.settings.setSramShiftingDisabled('dev1', true);
    // …and the change signal it emits. The page must react to it.
    core.connection.signalChange(device);
    await tester.pump();

    expect(find.textContaining('Restore original shifting'), findsOneWidget);
    expect(find.textContaining('Set up SRAM control'), findsNothing);
  });
}
