import 'dart:async';

import 'package:bike_control/main.dart';
import 'package:bike_control/services/email_otp_auth_service.dart';
import 'package:bike_control/utils/i18n_extension.dart';
import 'package:flutter/services.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Sign-in without a social account: Supabase mails a six-digit code and the
/// rider types it back here.
///
/// Deliberately code-only rather than a clickable magic link — a link has to
/// travel back through `bikecontrol://`, which is fragile on Windows and Linux,
/// and corporate mail scanners routinely open (and thereby burn) one-shot
/// links before the rider ever sees them. A typed code works the same on every
/// platform, including web.
class EmailLoginForm extends StatefulWidget {
  const EmailLoginForm({
    super.key,
    required this.onSignedIn,
    EmailOtpAuth? auth,
    this.cooldown = resendCooldown,
  }) : _auth = auth;

  /// Called once the code has been redeemed and a session exists.
  final VoidCallback onSignedIn;

  final EmailOtpAuth? _auth;

  /// How long "send a new code" stays shut after a send. Overridable so tests
  /// don't have to sit out a real minute.
  final Duration cooldown;

  static const Key emailFieldKey = Key('email_login_email_field');
  static const Key sendButtonKey = Key('email_login_send_button');
  static const Key codeFieldKey = Key('email_login_code_field');
  static const Key errorKey = Key('email_login_error');
  static const Key resendButtonKey = Key('email_login_resend_button');
  static const Key changeEmailKey = Key('email_login_change_email');

  /// Matches Supabase's own per-address send limit; asking sooner just earns a
  /// 429, so the button counts down instead.
  static const Duration resendCooldown = Duration(seconds: 60);

  @override
  State<EmailLoginForm> createState() => _EmailLoginFormState();
}

class _EmailLoginFormState extends State<EmailLoginForm> {
  static final RegExp _emailPattern = RegExp(r'^[^@\s]+@[^@\s.]+\.[^@\s]+$');

  late final EmailOtpAuth _auth = widget._auth ?? SupabaseEmailOtpAuth();
  final TextEditingController _emailController = TextEditingController();

  /// The address the code went to; null while the rider is still typing one.
  String? _codeSentTo;
  String? _error;
  bool _busy = false;

  /// When "send a new code" opens up again; null before the first send.
  DateTime? _resendAllowedAt;
  Timer? _cooldownTimer;

  Duration get _cooldownLeft {
    final until = _resendAllowedAt;
    if (until == null) return Duration.zero;
    final left = until.difference(DateTime.now());
    return left.isNegative ? Duration.zero : left;
  }

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _sendCode({required bool isResend}) async {
    if (_busy) return;
    if (isResend && _cooldownLeft > Duration.zero) return;

    final email = (_codeSentTo ?? _emailController.text).trim();
    if (!_emailPattern.hasMatch(email)) {
      setState(() => _error = context.i18n.pleaseEnterAValidEmailAddress);
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _auth.sendCode(email);
      if (!mounted) return;
      setState(() {
        _codeSentTo = email;
        _busy = false;
      });
      _startCooldown();
    } catch (e, s) {
      recordError(e, s, context: 'Email OTP send');
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = _isRateLimited(e)
            ? context.i18n.tooManyCodeRequestsPleaseWait
            : context.i18n.couldNotSendTheCodePleaseTryAgain;
      });
    }
  }

  Future<void> _verify(String code) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _auth.verifyCode(email: _codeSentTo!, code: code);
      if (!mounted) return;
      setState(() => _busy = false);
      widget.onSignedIn();
    } catch (e, s) {
      recordError(e, s, context: 'Email OTP verify');
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = _isRateLimited(e)
            ? context.i18n.tooManyCodeRequestsPleaseWait
            : context.i18n.theCodeIsIncorrectOrExpired;
      });
    }
  }

  bool _isRateLimited(Object error) => error is AuthApiException && error.statusCode == '429';

  void _startCooldown() {
    _cooldownTimer?.cancel();
    setState(() => _resendAllowedAt = DateTime.now().add(widget.cooldown));
    // Only redraws the countdown label — the gate itself reads the deadline,
    // so a missed tick can never hand out an early code or withhold a due one.
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted || _cooldownLeft == Duration.zero) {
        timer.cancel();
        return;
      }
      setState(() {});
    });
  }

  void _backToEmailEntry() {
    _cooldownTimer?.cancel();
    setState(() {
      _codeSentTo = null;
      _resendAllowedAt = null;
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      spacing: 12,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_codeSentTo == null) ..._buildEmailEntry(context) else ..._buildCodeEntry(context),
        if (_error != null)
          Text(
            _error!,
            key: EmailLoginForm.errorKey,
            textAlign: TextAlign.center,
            style: TextStyle(color: Theme.of(context).colorScheme.destructive),
          ).small,
      ],
    );
  }

  List<Widget> _buildEmailEntry(BuildContext context) {
    return [
      TextField(
        key: EmailLoginForm.emailFieldKey,
        controller: _emailController,
        keyboardType: TextInputType.emailAddress,
        autofillHints: const [AutofillHints.email],
        textInputAction: TextInputAction.go,
        placeholder: Text(context.i18n.emailAddress),
        onSubmitted: (_) => _sendCode(isResend: false),
      ),
      Button.primary(
        key: EmailLoginForm.sendButtonKey,
        onPressed: _busy ? null : () => _sendCode(isResend: false),
        child: Text(context.i18n.sendMeACode),
      ),
    ];
  }

  List<Widget> _buildCodeEntry(BuildContext context) {
    return [
      Text(context.i18n.checkYourInbox, textAlign: TextAlign.center).small.bold,
      Text(
        context.i18n.weSentACodeTo(_codeSentTo!),
        textAlign: TextAlign.center,
      ).small.muted,
      Align(
        child: InputOTP(
          key: EmailLoginForm.codeFieldKey,
          children: List.generate(
            6,
            (_) => InputOTPChild.character(allowDigit: true),
          ),
          onChanged: (value) {
            final code = value.otpToString();
            if (code.length == 6) _verify(code);
          },
        ),
      ),
      Button.ghost(
        key: EmailLoginForm.resendButtonKey,
        onPressed: () => _sendCode(isResend: true),
        child: Builder(
          builder: (context) {
            final left = _cooldownLeft;
            return Text(
              left > Duration.zero
                  ? context.i18n.sendANewCodeIn((left.inMilliseconds / 1000).ceil())
                  : context.i18n.sendANewCode,
            );
          },
        ),
      ),
      Button.ghost(
        key: EmailLoginForm.changeEmailKey,
        onPressed: _backToEmailEntry,
        child: Text(context.i18n.useADifferentEmailAddress),
      ),
    ];
  }
}
