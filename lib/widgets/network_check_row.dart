import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../gen/l10n.dart';
import '../services/network_self_test/network_check.dart';
import '../services/network_self_test/network_probe_context.dart';
import 'ui/small_progress_indicator.dart';

/// id → row title (exhaustive switch, l10n keys from Task 9).
String networkCheckTitle(BuildContext context, NetworkCheckId id) {
  final l10n = AppLocalizations.of(context);
  return switch (id) {
    NetworkCheckId.methodListening => l10n.networkCheckMethodListening,
    NetworkCheckId.advertisedAddress => l10n.networkCheckAdvertisedAddress,
    NetworkCheckId.vpn => l10n.networkCheckVpn,
    NetworkCheckId.advertisementVisible => l10n.networkCheckAdvertisementVisible,
    NetworkCheckId.localNetworkPermission => l10n.networkCheckLocalNetworkPermission,
    NetworkCheckId.backend => l10n.networkCheckBackend,
    NetworkCheckId.resolveOwnHostname => l10n.networkCheckResolveOwnHostname,
    NetworkCheckId.tcpSelfConnect => l10n.networkCheckTcpSelfConnect,
    NetworkCheckId.guidedWatch => l10n.networkCheckGuidedWatch,
    NetworkCheckId.bonjourService => l10n.networkCheckBonjourService,
    NetworkCheckId.bonjourNsp => l10n.networkCheckBonjourNsp,
    NetworkCheckId.windowsMdnsResolver => l10n.networkCheckWindowsMdnsResolver,
    NetworkCheckId.networkProfile => l10n.networkCheckNetworkProfile,
    NetworkCheckId.firewallRule => l10n.networkCheckFirewallRule,
    NetworkCheckId.multicastLock => l10n.networkCheckMulticastLock,
  };
}

/// fix → button label (exhaustive switch). On Windows,
/// [NetworkFixId.useOsResponderForObc] reads as "Register through Bonjour"
/// (`networkFixRegisterBonjour`) since the OS responder there IS Bonjour;
/// elsewhere it reads as the generic `networkFixUseOsResponder`.
String networkFixLabel(BuildContext context, NetworkFixId fix) {
  final l10n = AppLocalizations.of(context);
  return switch (fix) {
    NetworkFixId.restartMethod => l10n.networkFixRestartMethod,
    NetworkFixId.useOsResponderForObc =>
      !kIsWeb && Platform.isWindows ? l10n.networkFixRegisterBonjour : l10n.networkFixUseOsResponder,
    NetworkFixId.useResponderForObc => l10n.networkFixUseResponder,
    NetworkFixId.switchToLocal => l10n.networkFixSwitchToLocal,
    NetworkFixId.openFirewallSettings => l10n.networkFixOpenFirewallSettings,
    NetworkFixId.openBonjourDownload => l10n.networkFixOpenBonjourDownload,
    NetworkFixId.openLocalNetworkSettings => l10n.networkFixOpenLocalNetworkSettings,
    // Never actually shown as a per-row fix button — checks never carry this
    // fix (only the troubleshooting page's footer does) — kept only so this
    // switch stays exhaustive.
    NetworkFixId.sendToSupport => l10n.networkTroubleshootSendToSupport,
  };
}

/// Optional plain-language hint under a non-pass row. Only these three check
/// ids get one, and only when they actually failed — a warn/unknown on the
/// same id isn't specific enough to justify the extra sentence.
String? networkCheckHint(BuildContext context, NetworkCheck check) {
  if (check.verdict != NetworkVerdict.fail) return null;
  final l10n = AppLocalizations.of(context);
  return switch (check.id) {
    NetworkCheckId.bonjourService => l10n.networkHintBonjourService,
    NetworkCheckId.bonjourNsp => l10n.networkHintBonjourNsp,
    NetworkCheckId.resolveOwnHostname => l10n.networkHintResolveFail,
    _ => null,
  };
}

String _verdictWord(AppLocalizations l10n, NetworkVerdict verdict) {
  return switch (verdict) {
    NetworkVerdict.pass => l10n.networkVerdictPass,
    NetworkVerdict.warn => l10n.networkVerdictWarn,
    NetworkVerdict.fail => l10n.networkVerdictFail,
    NetworkVerdict.unknown => l10n.networkVerdictUnknown,
    NetworkVerdict.skipped => l10n.networkVerdictSkipped,
  };
}

/// One row of the network self-test: a glyph + title + verdict, with an
/// optional hint, one-tap fixes, an expandable detail block, and — while the
/// guided-watch check is running — a live "what have we seen so far" list.
class NetworkCheckRow extends StatefulWidget {
  final NetworkCheck check;

  /// Shows a spinner instead of the verdict glyph while true.
  final bool running;

  /// Non-null renders the live guided-watch bullet list under the row.
  final WatchProgress? watch;

  final void Function(NetworkFixId fix)? onFix;
  final VoidCallback? onSkipWatch;

  const NetworkCheckRow({super.key, required this.check, this.running = false, this.watch, this.onFix, this.onSkipWatch});

  @override
  State<NetworkCheckRow> createState() => _NetworkCheckRowState();
}

class _NetworkCheckRowState extends State<NetworkCheckRow> {
  bool _detailExpanded = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final check = widget.check;

    final (icon, color) = switch (check.verdict) {
      NetworkVerdict.pass => (LucideIcons.check, const Color(0xFF22C55E)),
      NetworkVerdict.warn => (LucideIcons.circleAlert, const Color(0xFFF59E0B)),
      NetworkVerdict.fail => (LucideIcons.circleX, const Color(0xFFEF4444)),
      NetworkVerdict.unknown => (LucideIcons.circleHelp, cs.mutedForeground),
      NetworkVerdict.skipped => (LucideIcons.minus, cs.mutedForeground),
    };

    final leading = widget.running
        ? const RepaintBoundary(child: SmallProgressIndicator())
        : Icon(icon, size: 18, color: color);

    final hint = networkCheckHint(context, check);
    final watch = widget.watch;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
      decoration: BoxDecoration(
        color: cs.muted,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: widget.running ? cs.mutedForeground : color),
      ),
      child: Basic(
        leading: leading,
        title: Text(networkCheckTitle(context, check.id)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 6,
          children: [
            Text(_verdictWord(l10n, check.verdict)).xSmall.textMuted,
            if (hint != null) Text(hint).xSmall.textMuted,
            if (check.fixes.isNotEmpty)
              Wrap(
                spacing: 8,
                children: [
                  for (final fix in check.fixes.take(2))
                    Button.outline(
                      style: ButtonStyle.outline(size: ButtonSize.small),
                      onPressed: widget.onFix == null ? null : () => widget.onFix!(fix),
                      child: Text(networkFixLabel(context, fix)),
                    ),
                ],
              ),
            if (check.detail.isNotEmpty) _detailSection(context, check),
            if (watch != null) _watchSection(context, l10n, watch),
          ],
        ),
      ),
    );
  }

  Widget _detailSection(BuildContext context, NetworkCheck check) {
    final entries = check.detail.entries.toList()..sort((a, b) => a.key.compareTo(b.key));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 4,
      children: [
        Button.ghost(
          style: ButtonStyle.ghost(size: ButtonSize.xSmall).withPadding(padding: EdgeInsets.zero),
          onPressed: () => setState(() => _detailExpanded = !_detailExpanded),
          child: Icon(_detailExpanded ? LucideIcons.chevronUp : LucideIcons.chevronDown, size: 14),
        ),
        if (_detailExpanded)
          Text(
            entries.map((e) => '${e.key}: ${e.value}').join('\n'),
            style: const TextStyle(fontFamily: 'monospace', fontFamilyFallback: ['Courier'], fontSize: 11),
          ),
      ],
    );
  }

  Widget _watchSection(BuildContext context, AppLocalizations l10n, WatchProgress watch) {
    final app = widget.check.detail['app'] ?? '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 6,
      children: [
        Text(l10n.networkWatchPrompt(app)).xSmall.textMuted,
        _watchBullet(context, l10n.networkWatchFoundUs(app), watch.browsed),
        _watchBullet(context, l10n.networkWatchResolved, watch.resolved),
        _watchBullet(context, l10n.networkWatchAddressAsks(watch.addressAsks), watch.addressAsks > 0),
        _watchBullet(context, l10n.networkWatchConnected, watch.connected),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('${watch.remaining.inSeconds}s').xSmall.textMuted,
            Button.ghost(
              style: ButtonStyle.ghost(size: ButtonSize.small),
              onPressed: widget.onSkipWatch,
              child: Text(l10n.networkWatchSkip),
            ),
          ],
        ),
      ],
    );
  }

  Widget _watchBullet(BuildContext context, String text, bool active) {
    final cs = Theme.of(context).colorScheme;
    return Text(
      '• $text',
      style: TextStyle(fontSize: 12, color: active ? cs.foreground : cs.mutedForeground),
    );
  }
}
