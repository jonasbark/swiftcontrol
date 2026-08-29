import 'package:bike_control/gen/l10n.dart';
import 'package:bike_control/main.dart' show OtherLocalizationsDelegate;
import 'package:bike_control/pages/onboarding/steps/step_connection.dart';
import 'package:bike_control/utils/actions/base_actions.dart' show StubActions;
import 'package:bike_control/utils/core.dart';
import 'package:bike_control/utils/keymap/apps/fulgaz.dart';
import 'package:bike_control/utils/keymap/apps/supported_app.dart';
import 'package:bike_control/utils/keymap/apps/tacx.dart';
import 'package:bike_control/utils/requirements/multi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The connection step promises the rider a specific thing to look for. For
/// apps that browse the network that promise is an advertisement; FulGaz only
/// scans Bluetooth, so telling it to watch the network sends the rider hunting
/// for something that will never appear.
///
/// Deliberately on the plain test binding rather than the snapshot harness:
/// that one selects IntegrationTestWidgetsFlutterBinding, which co-running
/// files poison with a stray app_links platform-stream error — the hazard
/// sram_states_snapshot_test already warns about.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    core.settings.prefs = await SharedPreferences.getInstance();
    core.actionHandler = StubActions();
  });

  Future<void> pumpConnectionStep(WidgetTester tester, SupportedApp app) async {
    core.settings.setTrainerApp(app);
    await core.settings.setLastTarget(Target.otherDevice);
    await tester.pumpWidget(
      ShadcnApp(
        debugShowCheckedModeBanner: false,
        localizationsDelegates: [
          ...ShadcnLocalizations.localizationsDelegates,
          const OtherLocalizationsDelegate(),
          AppLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.delegate.supportedLocales,
        locale: const Locale('en'),
        theme: ThemeData(colorScheme: ColorSchemes.lightSlate, radius: 0.7),
        home: Scaffold(
          child: SingleChildScrollView(
            child: Builder(
              builder: (context) => onboardingConnectionBody(
                context,
                app: app,
                target: Target.otherDevice,
                hasTrainer: false,
                trainerName: null,
                onUpdate: () {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
  }

  testWidgets('FulGaz is told to look for a Bluetooth trainer', (tester) async {
    await pumpConnectionStep(tester, FulGaz());
    final l10n = AppLocalizations.current;

    expect(find.text(l10n.onboardingConnectionSubtitleBluetooth('FulGaz')), findsOneWidget);
    expect(find.text(l10n.onboardingConnectionSubtitleNetwork('FulGaz')), findsNothing);
  });

  testWidgets('apps that browse the network keep the network wording', (tester) async {
    final tacx = Tacx();
    await pumpConnectionStep(tester, tacx);
    final l10n = AppLocalizations.current;

    expect(find.text(l10n.onboardingConnectionSubtitleNetwork(tacx.name)), findsOneWidget);
    expect(find.text(l10n.onboardingConnectionSubtitleBluetooth(tacx.name)), findsNothing);
  });
}
