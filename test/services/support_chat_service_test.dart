// Bug 1 (usage-fixes round): `fetchOpenIssues()` filtered `is_public = true`
// but never filtered by `status`, so issues already marked `solved` (website
// migration 20260515000000_add_issue_status_visibility.sql added
// `status text NOT NULL DEFAULT 'open' CHECK (status IN ('open','solved'))`)
// kept showing in the Known Issues section despite the method's own name.
// This pins the actual outgoing query — wiring a real SupabaseClient to a
// fake HTTP transport (the same "swap the transport, keep the real types"
// approach feedback_submission_service_test.dart and
// support_chat_page_test.dart use) so the real postgrest query-builder call
// is exercised, not a hand-rolled stand-in that could drift from it.
import 'dart:convert';

import 'package:bike_control/services/support_chat_service.dart';
import 'package:bike_control/utils/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _FakeIssuesHttp extends http.BaseClient {
  final List<http.Request> issuesRequests = [];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final req = request as http.Request;
    if (request.url.path.endsWith('/rest/v1/issues')) {
      issuesRequests.add(req);
      return _json(request, <dynamic>[]);
    }
    return _json(request, <String, dynamic>{}, status: 404);
  }

  // postgrest's response parsing does `response.request!.method` — the
  // `StreamedResponse` must carry the original request back or that
  // null-check blows up before our query ever gets asserted on.
  http.StreamedResponse _json(http.BaseRequest request, dynamic body, {int status = 200}) {
    return http.StreamedResponse(
      Stream.value(utf8.encode(jsonEncode(body))),
      status,
      request: request,
      headers: const {'content-type': 'application/json'},
    );
  }
}

void main() {
  late _FakeIssuesHttp fakeHttp;
  late SupabaseClient client;
  late SupportChatService service;

  setUp(() async {
    // fetchOpenIssues() reads core.settings.getTrainerApp() directly (the
    // ambient singleton, not an injected Settings) — prefs must exist before
    // that call or it throws. Same setUp shape as help_center_sections_test.dart.
    SharedPreferences.setMockInitialValues({});
    core.settings.prefs = await SharedPreferences.getInstance();

    fakeHttp = _FakeIssuesHttp();
    client = SupabaseClient(
      'https://example.test',
      'test-anon-key',
      httpClient: fakeHttp,
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
    service = SupportChatService(supabase: client, httpClient: fakeHttp);
  });

  tearDown(() => client.dispose());

  group('fetchOpenIssues', () {
    test('filters to status=open, not just is_public — solved issues must not come back', () async {
      await service.fetchOpenIssues();

      expect(fakeHttp.issuesRequests, hasLength(1));
      final uri = fakeHttp.issuesRequests.single.url;
      expect(uri.queryParameters['is_public'], 'eq.true', reason: 'sanity: the existing filter is still there');
      expect(
        uri.queryParameters['status'],
        'eq.open',
        reason: 'fetchOpenIssues must exclude solved issues despite its own name — see Bug 1',
      );
    });
  });
}
