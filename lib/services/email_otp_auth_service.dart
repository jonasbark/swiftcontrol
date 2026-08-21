import 'package:bike_control/utils/core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Email sign-in with a one-time code: Supabase mails a six-digit code, the
/// rider types it back. Kept behind an interface so the sign-in form can be
/// tested without a live Supabase, mirroring [SupportChatService]'s injection.
abstract class EmailOtpAuth {
  /// Mails a fresh sign-in code to [email], creating the account on first use.
  Future<void> sendCode(String email);

  /// Redeems [code] for a session. Throws [AuthException] when it is wrong,
  /// expired, or already used.
  Future<void> verifyCode({required String email, required String code});
}

class SupabaseEmailOtpAuth implements EmailOtpAuth {
  SupabaseEmailOtpAuth({SupabaseClient? supabase}) : _supabase = supabase ?? core.supabase;

  final SupabaseClient _supabase;

  @override
  Future<void> sendCode(String email) => _supabase.auth.signInWithOtp(email: email);

  @override
  Future<void> verifyCode({required String email, required String code}) => _supabase.auth.verifyOTP(
    email: email,
    token: code,
    // `email` covers both templates the flow can produce: `magiclink` for a
    // returning rider and `signup` for one Supabase just created.
    type: OtpType.email,
  );
}
