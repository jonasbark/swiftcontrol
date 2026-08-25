// Feedback-routing round: the trainer-feedback box's three buttons ("Works"
// / "No difference" / "Not working") used to all open a support chat
// prefilled with just the tapped label — ~16% of support chats arrived as
// that unchanged label with zero added detail, unanswerable as filed. Now:
// "Works" records the submission and acknowledges it in place (a toast),
// never opening a chat; "No difference"/"Not working" route into the Help
// Center's "Your setup" section instead of straight into the chat, carrying
// the same trainer-specific diagnostic payload (telemetry builder,
// diagnostic preview, screenshot, feedback key) so continuing from there
// into "Tell us what's wrong" doesn't lose it. See
// help_center_support_context.dart for the value object that carries that
// payload.
//
// Deliberately never awaits telemetryBuilder()/diagnosticPreviewFuture: both
// bottom out in the real, unmocked debugText() -> DebugDiagnostics.gather()
// -> MdnsDiscoveryScan().run(), which stalls for minutes rather than failing
// fast in this sandbox (no test anywhere in this suite calls the real
// debugText() for that reason). Propagation is verified with reference
// identity instead — proof the exact same builder/future/attachment objects
// reach SupportChatPage, not a rebuilt copy — which is what "the launch
// context reaches SupportChatPage" actually requires.
import 'package:bike_control/bluetooth/devices/proxy/proxy_device.dart';
import 'package:bike_control/gen/l10n.dart';
import 'package:bike_control/main.dart' show OtherLocalizationsDelegate, navigatorKey;
import 'package:bike_control/pages/help_center/help_center_page.dart';
import 'package:bike_control/pages/proxy_device_details.dart';
import 'package:bike_control/pages/support_chat/support_chat_page.dart';
import 'package:bike_control/utils/actions/base_actions.dart';
import 'package:bike_control/utils/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:universal_ble/universal_ble.dart';

Future<void> main() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  final l10n = await AppLocalizations.load(const Locale('en'));

  // HelpCenterPage's "Known issues" section fires a real, unmocked network
  // fetch on initState (same as help_center_page_test.dart) — point Supabase
  // at a bogus loopback endpoint so that fails fast (connection refused)
  // instead of hanging, and SupportChatPage's default SupportChatService()
  // has a real (if unusable) client to read `auth.currentSession` from.
  setUpAll(() async {
    await initializeDateFormatting();
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'http://127.0.0.1:9',
      anonKey: 'proxy-device-details-feedback-test-anon-key',
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

  ProxyDevice device() => ProxyDevice(BleDevice(deviceId: 'x', name: 'Wahoo KICKR'));

  // The feedback box (and, on the pushed Help Center page, the support row)
  // sits below the fold at the default 800x600 test viewport — scroll it
  // into view first so the tap actually lands on it instead of silently
  // missing (Flutter still "succeeds" a tap dispatched outside the render
  // tree's bounds, it just never reaches the widget).
  Future<void> tapKey(WidgetTester tester, String key) async {
    final finder = find.byKey(ValueKey(key));
    await tester.ensureVisible(finder);
    await tester.pump();
    await tester.tap(finder);
  }

  // Wired to the app's real navigatorKey (buildToast reads
  // navigatorKey.currentContext) and the fuller shadcn delegate set, matching
  // network_troubleshooting_page_test.dart's toast-testing setup.
  Future<void> pumpPage(WidgetTester tester, ProxyDevice device) async {
    await tester.pumpWidget(
      ShadcnApp(
        debugShowCheckedModeBanner: false,
        navigatorKey: navigatorKey,
        localizationsDelegates: [
          ...ShadcnLocalizations.localizationsDelegates,
          const OtherLocalizationsDelegate(),
          AppLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.delegate.supportedLocales,
        home: ProxyDeviceDetailsPage(device: device),
      ),
    );
    await tester.pump();
  }

  testWidgets('Works records the submission and toasts a thanks — it never pushes a chat or the Help Center', (
    tester,
  ) async {
    final trainer = device();
    await pumpPage(tester, trainer);

    expect(core.settings.getFeedbackSubmitted(trainer.trainerKey), isFalse);
    expect(find.byKey(const ValueKey('feedback-works')), findsOneWidget);

    await tapKey(tester, 'feedback-works');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(core.settings.getFeedbackSubmitted(trainer.trainerKey), isTrue);
    expect(find.byType(HelpCenterPage), findsNothing);
    expect(find.byType(SupportChatPage), findsNothing);
    expect(find.text(l10n.thanksForFeedback), findsOneWidget);

    // The toast schedules its own 3s auto-close Timer (buildToast's default
    // LOGLEVEL_INFO duration) — let it fire so no pending Timer trips
    // flutter_test's end-of-test "!timersPending" invariant.
    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('Not working routes into the Help Center focused on Your setup, with the trainer payload attached', (
    tester,
  ) async {
    final trainer = device();
    await pumpPage(tester, trainer);

    await tapKey(tester, 'feedback-not-working');
    await tester.pump();
    // Not pumpAndSettle: HelpCenterPage's "Known issues" section fires a
    // real, unmocked network fetch on initState.
    await tester.pump(const Duration(milliseconds: 400));

    expect(core.settings.getFeedbackSubmitted(trainer.trainerKey), isTrue);
    expect(find.byType(SupportChatPage), findsNothing, reason: 'routes through the Help Center, not straight to chat');
    expect(find.byType(HelpCenterPage), findsOneWidget);

    final page = tester.widget<HelpCenterPage>(find.byType(HelpCenterPage));
    expect(page.focus, HelpCenterFocus.yourSetup);
    final launchContext = page.launchContext;
    expect(launchContext, isNotNull, reason: 'the trainer-specific payload must ride along');
    expect(launchContext!.feedbackKey, 'feedbackNotWorking');
    expect(launchContext.diagnosticPreviewFuture, isNotNull);
  });

  testWidgets('No difference (shown once feedback was already submitted) also routes into the Help Center', (
    tester,
  ) async {
    final trainer = device();
    await core.settings.setFeedbackSubmitted(trainer.trainerKey, true);
    await pumpPage(tester, trainer);

    expect(find.byKey(const ValueKey('feedback-no-difference')), findsOneWidget);
    await tapKey(tester, 'feedback-no-difference');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(HelpCenterPage), findsOneWidget);
    final page = tester.widget<HelpCenterPage>(find.byType(HelpCenterPage));
    expect(page.focus, HelpCenterFocus.yourSetup);
    expect(page.launchContext?.feedbackKey, 'feedbackNoDifference');
  });

  testWidgets(
    'continuing from the Help Center "Tell us what\'s wrong" row carries that same payload into the chat, '
    'composer left empty',
    (tester) async {
      final trainer = device();
      await pumpPage(tester, trainer);

      await tapKey(tester, 'feedback-not-working');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(HelpCenterPage), findsOneWidget);
      final launchContext = tester.widget<HelpCenterPage>(find.byType(HelpCenterPage)).launchContext!;
      expect(launchContext.feedbackKey, 'feedbackNotWorking');

      await tapKey(tester, 'help-center-chat-with-support');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byType(SupportChatPage), findsOneWidget);
      final chatPage = tester.widget<SupportChatPage>(find.byType(SupportChatPage));
      expect(chatPage.initialText, isNull, reason: 'the label must not prefill the composer body any more');
      // Reference equality, not content equality: proves ContactCommunitySection
      // handed SupportChatPage the *exact* trainer-specific objects
      // _routeToHelpCenter gathered, rather than rebuilding a fresh generic
      // payload the way it does when launchContext is absent.
      expect(identical(chatPage.telemetryBuilder, launchContext.telemetryBuilder), isTrue);
      expect(identical(chatPage.diagnosticPreviewFuture, launchContext.diagnosticPreviewFuture), isTrue);
      expect(identical(chatPage.initialAttachment, launchContext.initialAttachment), isTrue);
    },
  );
}
