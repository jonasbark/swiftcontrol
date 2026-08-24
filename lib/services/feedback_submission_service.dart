// In-app feedback: a rider taps thumbs up/down, writes a note, and it lands
// in the `submit-feedback` edge function. The session may be anonymous — no
// sign-in is required to leave feedback — but the composer can offer to link
// an email afterwards so we can follow up.
import 'dart:io';

import 'package:bike_control/main.dart' show recordError;
import 'package:bike_control/utils/core.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

enum FeedbackSentiment { up, down }

enum FeedbackKind { suggestion, complaint }

class FeedbackSubmissionException implements Exception {
  const FeedbackSubmissionException(this.message);

  final String message;

  @override
  String toString() => 'FeedbackSubmissionException: $message';
}

/// Submits rider feedback to the `submit-feedback` edge function, creating an
/// anonymous Supabase session on demand, and offers a follow-up flow that
/// links an email address to that session.
class FeedbackSubmissionService {
  FeedbackSubmissionService({SupabaseClient? client}) : _client = client ?? core.supabase;

  static const _submitFunction = 'submit-feedback';

  final SupabaseClient _client;

  /// True when the current session has no confirmed email — either there is
  /// no session yet, or the signed-in user is anonymous.
  bool get isAnonymous {
    final user = _client.auth.currentSession?.user;
    if (user == null) return true;
    if (user.isAnonymous) return true;
    final email = user.email;
    return email == null || email.isEmpty;
  }

  /// Ensures a session (anonymous if none), then invokes the submit-feedback
  /// edge function. Throws [FeedbackSubmissionException] on any failure so
  /// the composer can keep the text and offer retry.
  Future<void> submit({
    required FeedbackSentiment sentiment,
    required FeedbackKind kind,
    required String body,
  }) async {
    await _ensureSession();

    final payload = <String, dynamic>{
      'sentiment': sentiment.name,
      'kind': kind.name,
      'body': body,
      ...await _contextFields(),
    };

    try {
      await _client.functions.invoke(_submitFunction, body: payload);
    } catch (e, s) {
      await recordError(e, s, context: 'FeedbackSubmissionService.submit');
      throw const FeedbackSubmissionException('Failed to submit feedback');
    }
  }

  /// Starts linking [email] to the anonymous session (updateUser → OTP mail).
  Future<void> beginEmailLink(String email) async {
    try {
      await _client.auth.updateUser(UserAttributes(email: email));
    } catch (e, s) {
      await recordError(e, s, context: 'FeedbackSubmissionService.beginEmailLink');
      throw const FeedbackSubmissionException('Failed to start email verification');
    }
  }

  /// Confirms the 6-digit [token] for [email] (OtpType.emailChange).
  Future<void> confirmEmailLink({required String email, required String token}) async {
    try {
      await _client.auth.verifyOTP(type: OtpType.emailChange, email: email, token: token);
    } catch (e, s) {
      await recordError(e, s, context: 'FeedbackSubmissionService.confirmEmailLink');
      throw const FeedbackSubmissionException('Failed to confirm the verification code');
    }
  }

  Future<void> _ensureSession() async {
    if (_client.auth.currentSession != null) return;
    try {
      await _client.auth.signInAnonymously();
    } catch (e, s) {
      await recordError(e, s, context: 'FeedbackSubmissionService.submit.signInAnonymously');
      throw const FeedbackSubmissionException('Failed to start a session');
    }
  }

  Future<Map<String, dynamic>> _contextFields() async {
    final fields = <String, dynamic>{'platform': _platform()};

    try {
      fields['locale'] = Intl.getCurrentLocale();
    } catch (e, s) {
      await recordError(e, s, context: 'FeedbackSubmissionService.submit.locale');
    }

    try {
      final info = await PackageInfo.fromPlatform();
      fields['app_version'] = info.version;
    } catch (e, s) {
      await recordError(e, s, context: 'FeedbackSubmissionService.submit.packageInfo');
    }

    return fields;
  }

  String _platform() {
    if (kIsWeb) return 'web';
    return Platform.operatingSystem;
  }
}
