// Usage-fix round 3 (Jonas): the chat's account-link card offered only
// email + OTP; this adds Google/Apple. `SupportAccountLinkCard` talks to a
// real `SupabaseClient` through `FeedbackSubmissionService` — same "swap the
// transport, keep the real types" approach test/services/
// feedback_submission_service_test.dart already uses — so these tests
// exercise the actual `linkIdentityWithIdToken` request shape, not a mock.
//
// The critical thing this pins: linking (not signing in) keeps the
// session's user id unchanged, so a chat already written under the
// anonymous session doesn't get orphaned by adding a Google/Apple identity
// to it. See support_account_link_card.dart's file header for the full
// investigation.
//
// Platform gating (Google: Android/iOS, Apple: iOS/macOS, mirroring
// LoginPage's native-vs-browser-redirect split) is driven by
// `defaultTargetPlatform` rather than `dart:io`'s `Platform` specifically so
// `debugDefaultTargetPlatformOverride` can force it here regardless of which
// OS actually runs the test — see social_sign_in.dart.
import 'dart:convert';

import 'package:bike_control/gen/l10n.dart';
import 'package:bike_control/pages/support_chat/widgets/support_account_link_card.dart';
import 'package:bike_control/services/feedback_submission_service.dart';
import 'package:bike_control/utils/auth/social_sign_in.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:sign_in_button/sign_in_button.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Fake transport for the subset of Supabase's Auth API
/// [FeedbackSubmissionService] can reach, including the id-token grant
/// `linkIdentityWithIdToken`/`signInWithIdToken` both use
/// (`/auth/v1/token?grant_type=id_token`).
class _FakeAuthHttp extends http.BaseClient {
  final List<http.Request> signupRequests = [];
  final List<http.Request> idTokenRequests = [];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final req = request as http.Request;
    final path = request.url.path;

    if (path.endsWith('/auth/v1/signup')) {
      signupRequests.add(req);
      return _json(_sessionJson(anonymous: true));
    }
    if (path.endsWith('/auth/v1/token') && request.url.queryParameters['grant_type'] == 'id_token') {
      idTokenRequests.add(req);
      // Same user id as every other fixture here — linking must not swap it
      // out for a different one (that would be the orphaning bug).
      return _json(_sessionJson(anonymous: false, email: 'rider@gmail.com'));
    }
    return _json(<String, dynamic>{}, status: 404);
  }

  http.StreamedResponse _json(Map<String, dynamic> body, {int status = 200}) {
    return http.StreamedResponse(
      Stream.value(utf8.encode(jsonEncode(body))),
      status,
      headers: const {'content-type': 'application/json'},
    );
  }
}

Map<String, dynamic> _sessionJson({required bool anonymous, String? email}) {
  return {
    'access_token': 'test-access-token',
    'token_type': 'bearer',
    'expires_in': 3600,
    'refresh_token': 'test-refresh-token',
    'user': {
      'id': 'user-id',
      'aud': 'authenticated',
      'created_at': '2026-08-24T00:00:00Z',
      'app_metadata': <String, dynamic>{},
      'user_metadata': <String, dynamic>{},
      'is_anonymous': anonymous,
      if (email != null) 'email': email,
    },
  };
}

/// Runs [body] with `debugDefaultTargetPlatformOverride` set to [platform],
/// resetting it synchronously before returning — even on failure — so
/// Flutter's post-test invariant check (`debugAssertAllFoundationVarsUnset`,
/// which runs *inside* `testWidgets`'s own body, before `tearDown`/
/// `addTearDown` hooks ever fire) sees it unset again. Mirrors the pattern
/// Flutter's own test suite uses for the same variable, e.g.
/// `flutter/test/material/expansion_tile_test.dart`.
Future<void> withPlatform(TargetPlatform platform, Future<void> Function() body) async {
  debugDefaultTargetPlatformOverride = platform;
  try {
    await body();
  } finally {
    debugDefaultTargetPlatformOverride = null;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppLocalizations l10n;
  late _FakeAuthHttp fakeHttp;
  late SupabaseClient client;
  late FeedbackSubmissionService accountService;

  setUpAll(() async {
    l10n = await AppLocalizations.load(const Locale('en'));
  });

  setUp(() {
    fakeHttp = _FakeAuthHttp();
    client = SupabaseClient(
      'https://example.test',
      'test-anon-key',
      httpClient: fakeHttp,
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
    accountService = FeedbackSubmissionService(client: client);
  });

  tearDown(() {
    client.dispose();
  });

  Future<void> pumpCard(
    WidgetTester tester, {
    Future<GoogleIdTokenResult> Function()? googleIdTokenFetcher,
    Future<AppleIdTokenResult> Function()? appleIdTokenFetcher,
  }) {
    return tester.pumpWidget(
      ShadcnApp(
        debugShowCheckedModeBanner: false,
        localizationsDelegates: const [AppLocalizations.delegate],
        supportedLocales: AppLocalizations.delegate.supportedLocales,
        home: Scaffold(
          child: SupportAccountLinkCard(
            accountService: accountService,
            googleIdTokenFetcher: googleIdTokenFetcher,
            appleIdTokenFetcher: appleIdTokenFetcher,
          ),
        ),
      ),
    );
  }

  group('platform gating', () {
    testWidgets('shows both Google and Apple on iOS', (tester) async {
      await withPlatform(TargetPlatform.iOS, () async {
        await pumpCard(tester);
        await tester.pump();

        expect(find.byType(SignInButton), findsNWidgets(2));
      });
    });

    testWidgets('shows only Google on Android', (tester) async {
      await withPlatform(TargetPlatform.android, () async {
        await pumpCard(tester);
        await tester.pump();

        expect(find.byType(SignInButton), findsOneWidget);
      });
    });

    testWidgets('shows only Apple on macOS', (tester) async {
      await withPlatform(TargetPlatform.macOS, () async {
        await pumpCard(tester);
        await tester.pump();

        expect(find.byType(SignInButton), findsOneWidget);
      });
    });

    testWidgets('shows neither on windows — email remains the only path, unchanged from before', (tester) async {
      await withPlatform(TargetPlatform.windows, () async {
        await pumpCard(tester);
        await tester.pump();

        expect(find.byType(SignInButton), findsNothing);
        expect(find.byKey(const ValueKey('support-account-email-field')), findsOneWidget);
      });
    });
  });

  group('linking', () {
    testWidgets('Google: links onto the existing anonymous session instead of switching users', (tester) async {
      await withPlatform(TargetPlatform.android, () async {
        // A message was already sent under this anonymous session before the
        // card ever appears — the scenario the orphaning risk is about.
        await client.auth.recoverSession(jsonEncode(_sessionJson(anonymous: true)));
        final userIdBeforeLink = client.auth.currentSession!.user.id;

        await pumpCard(
          tester,
          googleIdTokenFetcher: () async => const GoogleIdTokenResult(idToken: 'fake-google-id-token'),
        );
        await tester.pump();

        await tester.tap(find.byType(SignInButton));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.byKey(const ValueKey('support-account-linked')), findsOneWidget);
        expect(fakeHttp.idTokenRequests, hasLength(1));
        expect(fakeHttp.signupRequests, isEmpty, reason: 'a session already existed — no new anonymous sign-in');
        expect(
          client.auth.currentSession!.user.id,
          userIdBeforeLink,
          reason: 'linking must not swap in a different user id — that would orphan the chat already written',
        );
        expect(client.auth.currentSession!.user.isAnonymous, isFalse);
      });
    });

    testWidgets('Apple: links onto the existing anonymous session', (tester) async {
      await withPlatform(TargetPlatform.iOS, () async {
        await client.auth.recoverSession(jsonEncode(_sessionJson(anonymous: true)));
        final userIdBeforeLink = client.auth.currentSession!.user.id;

        await pumpCard(
          tester,
          appleIdTokenFetcher: () async => const AppleIdTokenResult(idToken: 'fake-apple-id-token', rawNonce: 'nonce'),
        );
        await tester.pump();

        await tester.tap(find.byType(SignInButton).last);
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.byKey(const ValueKey('support-account-linked')), findsOneWidget);
        expect(client.auth.currentSession!.user.id, userIdBeforeLink);
      });
    });

    testWidgets('Google with no prior session: creates one first (header Sign In tapped before any message)', (
      tester,
    ) async {
      await withPlatform(TargetPlatform.android, () async {
        expect(client.auth.currentSession, isNull);

        await pumpCard(
          tester,
          googleIdTokenFetcher: () async => const GoogleIdTokenResult(idToken: 'fake-google-id-token'),
        );
        await tester.pump();

        await tester.tap(find.byType(SignInButton));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.byKey(const ValueKey('support-account-linked')), findsOneWidget);
        expect(fakeHttp.signupRequests, hasLength(1), reason: 'ensureSession creates the anonymous session first');
        expect(fakeHttp.idTokenRequests, hasLength(1));
      });
    });

    testWidgets('a failed Google token fetch records the error and shows the generic failure message', (
      tester,
    ) async {
      await withPlatform(TargetPlatform.android, () async {
        await client.auth.recoverSession(jsonEncode(_sessionJson(anonymous: true)));

        await pumpCard(tester, googleIdTokenFetcher: () async => throw Exception('user cancelled'));
        await tester.pump();

        await tester.tap(find.byType(SignInButton));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull, reason: 'never swallowed — recordError catches it, not a rethrow');
        expect(find.byKey(const ValueKey('support-account-linked')), findsNothing);
        expect(find.text(l10n.supportAccountLinkFailed), findsOneWidget);
        expect(fakeHttp.idTokenRequests, isEmpty, reason: 'the token fetch itself failed — never reaches Supabase');
      });
    });
  });
}
