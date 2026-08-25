// FeedbackSubmissionService talks to a real SupabaseClient (auth + edge
// functions), so rather than inventing a bespoke interface for it, these
// tests wire that real client to a fake HTTP transport — the same "swap the
// transport, keep the real types" approach package:http's testing.dart
// documents. That lets the service exercise its actual session logic
// (currentSession / signInAnonymously / recoverSession) without a network.
import 'dart:convert';

import 'package:bike_control/services/feedback_submission_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Fake transport standing in for Supabase's Auth + Functions REST APIs.
/// Records every request it sees and replays canned responses, keyed by URL
/// path, for the handful of endpoints [FeedbackSubmissionService] can reach.
class _FakeSupabaseHttp extends http.BaseClient {
  final List<http.Request> signupRequests = [];
  final List<http.Request> functionRequests = [];
  final List<http.Request> userRequests = [];
  final List<http.Request> verifyRequests = [];
  final List<http.Request> idTokenRequests = [];

  Object? signInAnonymouslyError;
  int functionStatus = 200;
  Map<String, dynamic> functionResponseBody = {'id': 'feedback-1'};
  bool idTokenLinkError = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final req = request as http.Request;
    final path = request.url.path;

    if (path.contains('/functions/v1/')) {
      functionRequests.add(req);
      return _json(functionResponseBody, status: functionStatus);
    }
    if (path.endsWith('/auth/v1/signup')) {
      signupRequests.add(req);
      if (signInAnonymouslyError != null) {
        return _json({'msg': 'Anonymous sign-ins are disabled'}, status: 422);
      }
      return _json(_sessionJson(anonymous: true));
    }
    if (path.endsWith('/auth/v1/user')) {
      userRequests.add(req);
      return _json(_sessionJson(anonymous: false, email: 'rider@example.com')['user'] as Map<String, dynamic>);
    }
    if (path.endsWith('/auth/v1/verify')) {
      verifyRequests.add(req);
      return _json(_sessionJson(anonymous: false, email: 'rider@example.com'));
    }
    if (path.endsWith('/auth/v1/token') && request.url.queryParameters['grant_type'] == 'id_token') {
      idTokenRequests.add(req);
      if (idTokenLinkError) {
        return _json({'msg': 'Identity is already linked to another user'}, status: 422);
      }
      // Same user id as every other fixture here — a real link response
      // keeps the id unchanged; only `is_anonymous`/`email` flip.
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

/// A Supabase auth session/user payload. `access_token` is not a real JWT, so
/// gotrue's expiry check (which parses the JWT `exp` claim) falls back to
/// "never expires" — exactly what a short-lived test needs.
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  PackageInfo.setMockInitialValues(
    appName: 'BikeControl',
    packageName: 'de.jonasbark.swiftcontrol',
    version: '6.4.0',
    buildNumber: '1',
    buildSignature: '',
  );

  late _FakeSupabaseHttp fakeHttp;
  late SupabaseClient client;
  late FeedbackSubmissionService service;

  setUp(() {
    fakeHttp = _FakeSupabaseHttp();
    client = SupabaseClient(
      'https://example.test',
      'test-anon-key',
      httpClient: fakeHttp,
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
    service = FeedbackSubmissionService(client: client);
  });

  tearDown(() => client.dispose());

  group('submit', () {
    test('with an existing session invokes submit-feedback with the full payload, no anonymous sign-in', () async {
      await client.auth.recoverSession(jsonEncode(_sessionJson(anonymous: false, email: 'rider@example.com')));

      await service.submit(sentiment: FeedbackSentiment.up, kind: FeedbackKind.suggestion, body: 'Love the app!');

      expect(fakeHttp.signupRequests, isEmpty);
      expect(fakeHttp.functionRequests, hasLength(1));

      final request = fakeHttp.functionRequests.single;
      expect(request.url.path, endsWith('/functions/v1/submit-feedback'));
      final payload = jsonDecode(request.body) as Map<String, dynamic>;
      expect(payload['sentiment'], 'up');
      expect(payload['kind'], 'suggestion');
      expect(payload['body'], 'Love the app!');
      expect(payload['platform'], isNotEmpty);
      expect(payload['locale'], isNotEmpty);
      expect(payload['app_version'], '6.4.0');
    });

    test('without a session signs in anonymously first, then submits', () async {
      expect(client.auth.currentSession, isNull);

      await service.submit(sentiment: FeedbackSentiment.down, kind: FeedbackKind.complaint, body: 'Bug report');

      expect(fakeHttp.signupRequests, hasLength(1));
      expect(fakeHttp.functionRequests, hasLength(1));
      expect(client.auth.currentSession, isNotNull);
      expect(client.auth.currentSession!.user.isAnonymous, isTrue);
    });

    test('a disabled anonymous sign-in is wrapped in FeedbackSubmissionException', () async {
      fakeHttp.signInAnonymouslyError = 'disabled';

      await expectLater(
        service.submit(sentiment: FeedbackSentiment.up, kind: FeedbackKind.suggestion, body: 'test'),
        throwsA(isA<FeedbackSubmissionException>()),
      );
      expect(fakeHttp.functionRequests, isEmpty, reason: 'never reaches the edge function without a session');
    });

    test('an edge-function error is wrapped in FeedbackSubmissionException', () async {
      await client.auth.recoverSession(jsonEncode(_sessionJson(anonymous: false, email: 'rider@example.com')));
      fakeHttp.functionStatus = 500;
      fakeHttp.functionResponseBody = {'error': 'boom'};

      await expectLater(
        service.submit(sentiment: FeedbackSentiment.up, kind: FeedbackKind.suggestion, body: 'test'),
        throwsA(isA<FeedbackSubmissionException>()),
      );
    });
  });

  group('isAnonymous', () {
    test('is true with no session at all', () {
      expect(client.auth.currentSession, isNull);
      expect(service.isAnonymous, isTrue);
    });

    test('is true for a session whose user is anonymous', () async {
      await client.auth.recoverSession(jsonEncode(_sessionJson(anonymous: true)));

      expect(service.isAnonymous, isTrue);
    });

    test('is false for a session with a confirmed email', () async {
      await client.auth.recoverSession(jsonEncode(_sessionJson(anonymous: false, email: 'rider@example.com')));

      expect(service.isAnonymous, isFalse);
    });
  });

  group('email link-up', () {
    setUp(() async {
      await client.auth.recoverSession(jsonEncode(_sessionJson(anonymous: true)));
    });

    test('beginEmailLink asks Supabase to start an email-change OTP', () async {
      await service.beginEmailLink('rider@example.com');

      expect(fakeHttp.userRequests, hasLength(1));
      final payload = jsonDecode(fakeHttp.userRequests.single.body) as Map<String, dynamic>;
      expect(payload['email'], 'rider@example.com');
    });

    test('confirmEmailLink verifies the OTP against the emailChange type', () async {
      await service.confirmEmailLink(email: 'rider@example.com', token: '123456');

      expect(fakeHttp.verifyRequests, hasLength(1));
      final payload = jsonDecode(fakeHttp.verifyRequests.single.body) as Map<String, dynamic>;
      expect(payload['email'], 'rider@example.com');
      expect(payload['token'], '123456');
      expect(payload['type'], 'email_change');
    });

    test('a rejected code is wrapped in FeedbackSubmissionException', () async {
      final erroringClient = SupabaseClient(
        'https://example.test',
        'test-anon-key',
        httpClient: _ErroringVerifyHttp(),
        authOptions: const AuthClientOptions(autoRefreshToken: false),
      );
      await erroringClient.auth.recoverSession(jsonEncode(_sessionJson(anonymous: true)));
      final erroringService = FeedbackSubmissionService(client: erroringClient);

      await expectLater(
        erroringService.confirmEmailLink(email: 'rider@example.com', token: '000000'),
        throwsA(isA<FeedbackSubmissionException>()),
      );

      await erroringClient.dispose();
    });
  });

  group('email link-up with no prior session', () {
    test('beginEmailLink creates an anonymous session first', () async {
      // Covers the chat's header "Sign In" button, which can be tapped
      // before any message — and therefore any session — exists yet.
      // Without this, `updateUser` would have no session to act on.
      expect(client.auth.currentSession, isNull);

      await service.beginEmailLink('rider@example.com');

      expect(fakeHttp.signupRequests, hasLength(1));
      expect(fakeHttp.userRequests, hasLength(1));
      expect(client.auth.currentSession, isNotNull);
    });
  });

  group('social identity linking', () {
    setUp(() async {
      await client.auth.recoverSession(jsonEncode(_sessionJson(anonymous: true)));
    });

    test('linkGoogleIdentity calls the id-token grant with link_identity — same user id preserved', () async {
      final userIdBeforeLink = client.auth.currentSession!.user.id;

      await service.linkGoogleIdentity(idToken: 'fake-google-id-token', accessToken: 'fake-access-token');

      expect(fakeHttp.idTokenRequests, hasLength(1));
      final request = fakeHttp.idTokenRequests.single;
      expect(request.url.queryParameters['grant_type'], 'id_token');
      final payload = jsonDecode(request.body) as Map<String, dynamic>;
      expect(payload['provider'], 'google');
      expect(payload['id_token'], 'fake-google-id-token');
      expect(payload['access_token'], 'fake-access-token');
      expect(payload['link_identity'], isTrue, reason: 'must link onto the current user, not sign in as a new one');
      expect(
        client.auth.currentSession!.user.id,
        userIdBeforeLink,
        reason: 'linking preserves the session/user id so anything already written under it stays attached',
      );
      expect(client.auth.currentSession!.user.isAnonymous, isFalse);
    });

    test('linkAppleIdentity calls the id-token grant with the Apple provider and nonce', () async {
      final userIdBeforeLink = client.auth.currentSession!.user.id;

      await service.linkAppleIdentity(idToken: 'fake-apple-id-token', nonce: 'raw-nonce');

      expect(fakeHttp.idTokenRequests, hasLength(1));
      final payload = jsonDecode(fakeHttp.idTokenRequests.single.body) as Map<String, dynamic>;
      expect(payload['provider'], 'apple');
      expect(payload['id_token'], 'fake-apple-id-token');
      expect(payload['nonce'], 'raw-nonce');
      expect(payload['link_identity'], isTrue);
      expect(client.auth.currentSession!.user.id, userIdBeforeLink);
    });

    test('linkGoogleIdentity with no prior session creates an anonymous one first', () async {
      final noSessionClient = SupabaseClient(
        'https://example.test',
        'test-anon-key',
        httpClient: fakeHttp,
        authOptions: const AuthClientOptions(autoRefreshToken: false),
      );
      final noSessionService = FeedbackSubmissionService(client: noSessionClient);
      expect(noSessionClient.auth.currentSession, isNull);

      await noSessionService.linkGoogleIdentity(idToken: 'fake-google-id-token');

      expect(fakeHttp.signupRequests, hasLength(1));
      expect(fakeHttp.idTokenRequests, hasLength(1));

      await noSessionClient.dispose();
    });

    test('a rejected link is wrapped in FeedbackSubmissionException, not swallowed', () async {
      fakeHttp.idTokenLinkError = true;

      await expectLater(
        service.linkGoogleIdentity(idToken: 'fake-google-id-token'),
        throwsA(isA<FeedbackSubmissionException>()),
      );
    });
  });
}

/// Minimal transport used only to exercise the verifyOTP failure path.
class _ErroringVerifyHttp extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    return http.StreamedResponse(
      Stream.value(utf8.encode(jsonEncode({'msg': 'Token has expired or is invalid'}))),
      403,
      headers: const {'content-type': 'application/json'},
    );
  }
}
