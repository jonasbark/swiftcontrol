import 'package:bike_control/gen/l10n.dart';
import 'package:bike_control/main.dart' show recordError;
import 'package:bike_control/services/feedback_submission_service.dart';
import 'package:bike_control/utils/auth/social_sign_in.dart';
import 'package:bike_control/widgets/ui/small_progress_indicator.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:sign_in_button/sign_in_button.dart';

/// Inline "Get the reply" card offering to link an account to the rider's
/// anonymous support-chat session — email (→ 6-digit code, the same
/// two-phase flow as `FeedbackThanksStep`) or, where the platform supports a
/// native id-token flow, Google/Apple — reusing [FeedbackSubmissionService]
/// for the actual Supabase calls since the account-linking logic isn't
/// feedback-specific.
///
/// Google/Apple deliberately *link* the identity onto the current session
/// (`FeedbackSubmissionService.linkGoogleIdentity`/`linkAppleIdentity`, which
/// call GoTrue's `linkIdentityWithIdToken`) rather than signing in the way
/// `LoginPage` does with the same token. The chat's session is anonymous and
/// already owns rows (the messages this rider just sent) — `signInWithIdToken`
/// would find-or-create a *different* user for that Google/Apple identity and
/// switch the client to it, orphaning the anonymous chat. Linking keeps the
/// session's user id (and therefore the chat) exactly as it was, just with a
/// permanent identity attached — confirmed by
/// support_account_link_card_test.dart, which asserts the session's user id
/// is unchanged after a simulated link.
///
/// The Google/Apple buttons only render where a native id-token flow exists
/// — Google on Android/iOS, Apple on iOS/macOS, matching `LoginPage`'s own
/// native-vs-browser-redirect split (see `social_sign_in.dart`). The
/// browser-redirect OAuth flow `LoginPage` falls back to on other platforms
/// signs in directly with no id-token step to link instead, and wiring up an
/// equivalent linking version of it (GoTrue's `getLinkIdentityUrl` + a
/// deep-link round trip) is out of scope here — on those platforms (Windows,
/// Linux, and Google on macOS) this card simply keeps offering email only,
/// unchanged from before.
///
/// [SupportChatPage] has two entry points that reveal this widget — the
/// post-send prompt and the header's "Sign In" button — and both converge on
/// this one instance, so there is exactly one state machine regardless of
/// which one the rider used.
class SupportAccountLinkCard extends StatefulWidget {
  final FeedbackSubmissionService accountService;

  /// Called once, right after a link/verify succeeds, so the parent can
  /// refresh anything that reads [FeedbackSubmissionService.isAnonymous]
  /// itself (the chat header).
  final VoidCallback? onLinked;

  /// Test seam: replaces the real Google-SDK token fetch — see
  /// support_account_link_card_test.dart.
  final Future<GoogleIdTokenResult> Function()? googleIdTokenFetcher;

  /// Test seam: replaces the real Sign in with Apple token fetch.
  final Future<AppleIdTokenResult> Function()? appleIdTokenFetcher;

  const SupportAccountLinkCard({
    super.key,
    required this.accountService,
    this.onLinked,
    this.googleIdTokenFetcher,
    this.appleIdTokenFetcher,
  });

  @override
  State<SupportAccountLinkCard> createState() => _SupportAccountLinkCardState();
}

class _SupportAccountLinkCardState extends State<SupportAccountLinkCard> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _codeController = TextEditingController();

  /// Null until [_sendLink] succeeds — then holds the address the code was
  /// sent to and the UI switches from the email field to the code field.
  String? _codeSentTo;
  bool _linked = false;
  bool _busy = false;
  bool _failed = false;

  @override
  void dispose() {
    _emailController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _sendLink() async {
    final email = _emailController.text.trim();
    if (email.isEmpty || _busy) return;
    setState(() {
      _busy = true;
      _failed = false;
    });
    try {
      await widget.accountService.beginEmailLink(email);
      if (!mounted) return;
      setState(() {
        _codeSentTo = email;
        _busy = false;
      });
    } catch (e, s) {
      await recordError(e, s, context: 'SupportAccountLinkCard.beginEmailLink');
      if (!mounted) return;
      setState(() {
        _busy = false;
        _failed = true;
      });
    }
  }

  Future<void> _verify() async {
    final email = _codeSentTo;
    final code = _codeController.text.trim();
    if (email == null || code.isEmpty || _busy) return;
    setState(() {
      _busy = true;
      _failed = false;
    });
    try {
      await widget.accountService.confirmEmailLink(email: email, token: code);
      if (!mounted) return;
      setState(() {
        _linked = true;
        _busy = false;
      });
      widget.onLinked?.call();
    } catch (e, s) {
      await recordError(e, s, context: 'SupportAccountLinkCard.confirmEmailLink');
      if (!mounted) return;
      setState(() {
        _busy = false;
        _failed = true;
      });
    }
  }

  Future<void> _linkWithGoogle() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _failed = false;
    });
    try {
      final fetch = widget.googleIdTokenFetcher ?? fetchGoogleIdToken;
      final token = await fetch();
      await widget.accountService.linkGoogleIdentity(idToken: token.idToken, accessToken: token.accessToken);
      if (!mounted) return;
      setState(() {
        _linked = true;
        _busy = false;
      });
      widget.onLinked?.call();
    } catch (e, s) {
      await recordError(e, s, context: 'SupportAccountLinkCard.linkGoogleIdentity');
      if (!mounted) return;
      setState(() {
        _busy = false;
        _failed = true;
      });
    }
  }

  Future<void> _linkWithApple() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _failed = false;
    });
    try {
      final fetch = widget.appleIdTokenFetcher ?? fetchAppleIdToken;
      final token = await fetch();
      await widget.accountService.linkAppleIdentity(idToken: token.idToken, nonce: token.rawNonce);
      if (!mounted) return;
      setState(() {
        _linked = true;
        _busy = false;
      });
      widget.onLinked?.call();
    } catch (e, s) {
      await recordError(e, s, context: 'SupportAccountLinkCard.linkAppleIdentity');
      if (!mounted) return;
      setState(() {
        _busy = false;
        _failed = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;

    if (_linked) {
      return Container(
        key: const ValueKey('support-account-linked'),
        margin: const EdgeInsets.fromLTRB(12, 6, 12, 0),
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: Colors.green.withAlpha(20),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.green),
        ),
        child: Row(
          children: [
            const Icon(LucideIcons.check, size: 16, color: Colors.green),
            const Gap(9),
            Expanded(
              child: Text(
                l10n.supportAccountLinkedNote,
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
              ),
            ),
          ],
        ),
      );
    }

    // Only offered ahead of the email step — once the rider has an email
    // code in flight, let that finish rather than also surfacing Google/Apple.
    final showSocialButtons = _codeSentTo == null && (supportsNativeGoogleSignIn || supportsNativeAppleSignIn);

    return Container(
      key: const ValueKey('support-account-link-card'),
      margin: const EdgeInsets.fromLTRB(12, 6, 12, 0),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: cs.muted.withAlpha(120),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l10n.supportAccountLinkTitle, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          const Gap(3),
          Text(l10n.supportAccountLinkBody, style: TextStyle(fontSize: 12.5, color: cs.mutedForeground)),
          const Gap(11),
          if (showSocialButtons) ...[
            if (supportsNativeGoogleSignIn) SignInButton(Buttons.google, onPressed: _linkWithGoogle),
            if (supportsNativeAppleSignIn) ...[
              if (supportsNativeGoogleSignIn) const Gap(8),
              SignInButton(Buttons.apple, onPressed: _linkWithApple),
            ],
            const Gap(11),
            Divider(child: Text(l10n.orSeparator).small.muted),
            const Gap(11),
          ],
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: _codeSentTo == null
                    ? TextField(
                        key: const ValueKey('support-account-email-field'),
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        placeholder: Text(l10n.emailAddress),
                      )
                    : TextField(
                        key: const ValueKey('support-account-code-field'),
                        controller: _codeController,
                        keyboardType: TextInputType.number,
                        placeholder: Text(l10n.feedbackEmailCodeHint),
                      ),
              ),
              const Gap(8),
              PrimaryButton(
                key: ValueKey(_codeSentTo == null ? 'support-account-email-send' : 'support-account-code-verify'),
                onPressed: _busy ? null : (_codeSentTo == null ? _sendLink : _verify),
                child: _busy
                    ? const SmallProgressIndicator()
                    : Text(_codeSentTo == null ? l10n.supportAccountLinkAddButton : l10n.feedbackEmailVerifyButton),
              ),
            ],
          ),
          if (_failed) ...[
            const Gap(8),
            Text(
              l10n.supportAccountLinkFailed,
              style: TextStyle(color: cs.destructive, fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }
}
