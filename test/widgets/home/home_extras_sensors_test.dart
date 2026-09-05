import 'package:bike_control/gen/l10n.dart';
import 'package:bike_control/pages/home/home_extras.dart';
import 'package:bike_control/pages/sensors/sensors_section.dart';
import 'package:bike_control/utils/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// V1 (wave 3): the standalone half of `SensorsSection`'s reachability.
/// `ProxyDeviceDetailsPage` is per-trainer — a rider who never bridges a
/// trainer through the app at all (standalone mode, the whole reason this
/// feature exists for riders who only use BikeControl as a plain heart rate
/// monitor) can never reach it there. `HomeExtras` is the app's home screen,
/// mounted unconditionally regardless of trainer connection state, so it is
/// the global entry point.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'http://127.0.0.1:9',
      anonKey: 'home-extras-sensors-test-anon-key',
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
  });

  Future<void> pumpExtras(WidgetTester tester) async {
    await tester.pumpWidget(
      ShadcnApp(
        localizationsDelegates: [
          ...ShadcnLocalizations.localizationsDelegates,
          AppLocalizations.delegate,
        ],
        supportedLocales: const [Locale('en')],
        home: Scaffold(
          child: HomeExtras(isMobile: false, onUpdate: () {}),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('offers a Sensors row alongside the other extra settings', (tester) async {
    await pumpExtras(tester);

    expect(find.text(AppLocalizations.current.sensorsSectionTitle), findsOneWidget);
  });

  testWidgets('tapping Sensors reaches the Sensors section with no trainer connected', (tester) async {
    await pumpExtras(tester);

    await tester.tap(find.text(AppLocalizations.current.sensorsSectionTitle));
    await tester.pumpAndSettle();

    expect(find.byType(SensorsSection), findsOneWidget);
  });
}
