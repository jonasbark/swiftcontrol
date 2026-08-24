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

  Object? signInAnonymouslyError;
  int functionStatus = 200;
  Map<String, dynamic> functionResponseBody = {'id': 'feedback-1'};

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
