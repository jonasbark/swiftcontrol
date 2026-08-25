// Feedback-routing round: the trainer-feedback buttons on the smart-trainer
// details page ("No difference"/"Not working") used to open a support chat
// directly, prefilled with the tapped label — see proxy_device_details.dart.
// They now route through HelpCenterPage's "Your setup" section instead, but
// the rich diagnostic payload the chat used to get (a screenshot, a
// trainer-specific TelemetrySnapshot builder, a formatted preview) must
// still reach SupportChatPage if the rider continues from there into
// "Tell us what's wrong" — ContactCommunitySection uses this value object
// for that handoff instead of gathering its own generic payload from
// scratch.
import 'package:bike_control/pages/support_chat/support_chat_page.dart' show TelemetryBuilder;
import 'package:bike_control/pages/support_chat/widgets/support_composer.dart' show StagedAttachment;

/// Bundles the trainer-specific support payload a Help Center entry point
/// (currently only the trainer-feedback buttons) gathered before pushing
/// [HelpCenterPage], so [ContactCommunitySection] can hand the exact same
/// payload to [SupportChatPage] instead of collecting a fresh, generic one.
class HelpCenterSupportContext {
  /// Which feedback button routed here (e.g. `feedbackNotWorking`). Already
  /// folded into [telemetryBuilder]'s payload — its `freetext` leads with
  /// this key — but kept here too so callers have it without re-parsing
  /// telemetry.
  final String feedbackKey;

  /// Re-gathers a fresh [TelemetrySnapshot] at send time, so a message sent
  /// well after the Help Center opened still reflects the trainer's current
  /// state rather than a stale compose-time snapshot.
  final TelemetryBuilder telemetryBuilder;

  /// One-shot preview of the diagnostic payload, resolved as the composer's
  /// diagnostics preview.
  final Future<String>? diagnosticPreviewFuture;

  /// Screenshot captured before the Help Center was pushed, pre-staged in
  /// the composer.
  final StagedAttachment? initialAttachment;

  const HelpCenterSupportContext({
    required this.feedbackKey,
    required this.telemetryBuilder,
    this.diagnosticPreviewFuture,
    this.initialAttachment,
  });
}
