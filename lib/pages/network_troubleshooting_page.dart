import 'dart:async';
import 'dart:io' show Platform, Process;

import 'package:bike_control/gen/l10n.dart';
import 'package:bike_control/main.dart' show recordError;
import 'package:bike_control/pages/support_chat/support_chat_page.dart';
import 'package:bike_control/services/debug_diagnostics.dart';
import 'package:bike_control/services/network_self_test/network_check.dart';
import 'package:bike_control/services/network_self_test/network_fixes.dart';
import 'package:bike_control/services/network_self_test/network_probe_context.dart';
import 'package:bike_control/services/network_self_test/network_self_test_engine.dart';
import 'package:bike_control/services/network_self_test/network_self_test_result.dart';
import 'package:bike_control/services/network_self_test/network_self_test_store.dart';
import 'package:bike_control/services/network_self_test/probes/active_probes.dart';
import 'package:bike_control/services/telemetry_snapshot.dart';
import 'package:bike_control/utils/core.dart';
import 'package:bike_control/utils/i18n_extension.dart';
import 'package:bike_control/widgets/logviewer.dart';
import 'package:bike_control/widgets/menu.dart' show debugText;
import 'package:bike_control/widgets/network_check_row.dart';
import 'package:bike_control/widgets/ui/small_progress_indicator.dart';
import 'package:bike_control/widgets/ui/toast.dart';
import 'package:dartx/dartx.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:prop/mdns/service_advertiser.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

/// `Platform.operatingSystem`-shaped, `kIsWeb`-aware — matches
/// [NetworkProbeContext.platform]'s documented shape. The page is never
/// actually reachable on web (its menu entry is gated), but every probe
/// context still needs a defined value there.
String platformString() => kIsWeb ? 'web' : Platform.operatingSystem;

/// Builds the real [NetworkProbeContext] for production, wiring every seam
/// to `core` or a default implementation (Tasks 5-7).
///
/// [NetworkSelfTestEngine]'s `contextBuilder` contract is synchronous, but
/// gathering [snapshot] itself (a [DebugDiagnostics.gather] call) is not —
/// so the snapshot is gathered once by the caller (the page's default engine
/// factory, below) *before* the engine exists, and handed in here rather
/// than fetched inline.
NetworkProbeContext buildProductionContext({DebugDiagnostics? snapshot, Object? snapshotError}) {
  return NetworkProbeContext(
    snapshot: snapshot,
    snapshotError: snapshotError,
    emulatorStarted: core.obpMdnsEmulator.isStarted.value,
    trainerAppConnected: core.obpMdnsEmulator.isConnected.value,
    trainerAppConnectedNow: () => core.obpMdnsEmulator.isConnected.value,
    trainerAppName: core.settings.getTrainerApp()?.name,
    backend: core.obpMdnsEmulator.activeBackend,
    advertisedHostname: core.obpMdnsEmulator.advertisedHostname,
    platform: platformString(),
    resolve: defaultResolve,
    tcpProbe: defaultTcpProbe,
    runProcess: (executable, arguments) => Process.run(executable, arguments).timeout(const Duration(seconds: 8)),
    queryLog: () {
      final advertiser = ServiceAdvertiser.instance;
      return advertiser is ResponderServiceAdvertiser ? advertiser.recentQueries : const [];
    },
    sleep: (d) => Future<void>.delayed(d),
    now: DateTime.now,
    onWatchProgress: (_) {},
  );
}

/// Guided, step-by-step "why can't my trainer app find BikeControl" page:
/// runs [NetworkSelfTestEngine] and renders its live progress, a one-tap
/// recommended fix, and ways to hand the result to support.
class NetworkTroubleshootingPage extends StatefulWidget {
  /// Test seam: builds the engine the page drives. Defaults to a real
  /// [NetworkSelfTestEngine] over [buildProductionContext] and the
  /// platform's default probes.
  final NetworkSelfTestEngine Function()? engineFactory;

  const NetworkTroubleshootingPage({super.key, this.engineFactory});

  @override
  State<NetworkTroubleshootingPage> createState() => _NetworkTroubleshootingPageState();
}

class _NetworkTroubleshootingPageState extends State<NetworkTroubleshootingPage> {
  NetworkSelfTestEngine? _engine;

  /// True from [initState] when the trainer app is already connected — shown
  /// instead of auto-starting, since a working connection has nothing to
  /// troubleshoot. Cleared once the rider taps through anyway.
  bool _showConnectedRefusal = false;

  @override
  void initState() {
    super.initState();
    if (kIsWeb) return;
    if (core.obpMdnsEmulator.isConnected.value) {
      _showConnectedRefusal = true;
    } else {
      _start();
    }
  }

  @override
  void dispose() {
    _engine?.cancel();
    super.dispose();
  }

  Future<void> _start() async {
    if (kIsWeb) return;
    final factory = widget.engineFactory;
    final NetworkSelfTestEngine engine;
    if (factory != null) {
      engine = factory();
    } else {
      DebugDiagnostics? snapshot;
      Object? snapshotError;
      try {
        snapshot = await DebugDiagnostics.gather(includeDiscovery: true);
      } catch (e, s) {
        recordError(e, s, context: 'NetworkTroubleshootingPage.snapshot');
        snapshotError = e;
      }
      // No explicit `probes:` here — the engine's own default construction
      // (see NetworkSelfTestEngine's constructor) is what wires
      // `engine.cancelWatch()` into the guided-watch probe's `isCancelled`
      // seam; a probe list built ahead of time and handed in wouldn't see
      // cancellation at all.
      engine = NetworkSelfTestEngine(contextBuilder: () => buildProductionContext(snapshot: snapshot, snapshotError: snapshotError));
    }
    if (!mounted) return;
    setState(() {
      _showConnectedRefusal = false;
      _engine = engine;
    });
    engine.run().then((result) {
      NetworkSelfTestStore.save(result);
      if (mounted) setState(() {});
    }).catchError((e, s) {
      recordError(e, s, context: 'NetworkSelfTest.page');
    });
  }

  Future<void> _runFix(NetworkFixId fix) async {
    if (fix == NetworkFixId.sendToSupport) {
      final result = _engine?.state.value.result;
      if (result != null && mounted) {
        _openSupport(context, result);
      }
      return;
    }
    await runNetworkFix(context, fix);
    // A full re-run: the checks are cheap and the watch row is skippable, so
    // there is no reason to re-verify just the one fixed check.
    await _start();
  }

  void _openSupport(BuildContext context, NetworkSelfTestResult result) {
    final debugFuture = debugText();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SupportChatPage(
          diagnosticPreviewFuture: debugFuture,
          initialText: 'Network self-test: ${result.toBundleString()}',
          telemetryBuilder: () async => TelemetrySnapshot.general(freetext: await debugFuture),
        ),
      ),
    );
  }

  /// Fixes that stop the OpenBikeControl server are greyed out while a
  /// trainer app is connected through it — they would drop a connection
  /// that works. `runNetworkFix` refuses them too (with a toast) should one
  /// slip through; this is just the visual half of that.
  static const _stopsServer = {NetworkFixId.restartMethod, NetworkFixId.useOsResponderForObc, NetworkFixId.useResponderForObc};

  bool _fixDisabled(NetworkFixId fix) => _stopsServer.contains(fix) && core.obpMdnsEmulator.isConnected.value;

  @override
  Widget build(BuildContext context) {
    final l10n = context.i18n;
    return Scaffold(
      headers: [
        AppBar(
          leading: [
            IconButton.ghost(
              icon: const Icon(LucideIcons.arrowLeft, size: 24),
              onPressed: () => Navigator.of(context).maybePop(),
            ),
          ],
          title: Text(
            l10n.networkTroubleshootingTitle,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600, letterSpacing: -0.3),
          ),
          backgroundColor: Theme.of(context).colorScheme.background,
        ),
        const Divider(),
      ],
      child: SingleChildScrollView(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: _showConnectedRefusal && _engine == null ? _refusalCard(context, l10n) : _engineSection(context, l10n),
            ),
          ),
        ),
      ),
    );
  }

  Widget _refusalCard(BuildContext context, AppLocalizations l10n) {
    final app = core.settings.getTrainerApp()?.name ?? '';
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 10,
        children: [
          Text(l10n.networkTroubleshootConnectedRefusal(app)),
          Button.outline(onPressed: _start, child: Text(l10n.networkTroubleshootRun)),
        ],
      ),
    );
  }

  Widget _engineSection(BuildContext context, AppLocalizations l10n) {
    final engine = _engine;
    if (engine == null) {
      return const SizedBox.shrink();
    }
    return ValueListenableBuilder<NetworkSelfTestState>(
      valueListenable: engine.state,
      builder: (context, state, _) {
        final result = state.result;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 12,
          children: [
            _headerCard(context, l10n, state),
            ..._checkRows(state),
            if (result != null) _footer(context, l10n, result),
          ],
        );
      },
    );
  }

  Widget _headerCard(BuildContext context, AppLocalizations l10n, NetworkSelfTestState state) {
    final result = state.result;
    if (result == null) {
      return Card(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const RepaintBoundary(child: SmallProgressIndicator()),
            Button.ghost(
              key: const ValueKey('network-cancel'),
              onPressed: () => _engine?.cancel(),
              child: Text(l10n.networkTroubleshootCancel),
            ),
          ],
        ),
      );
    }

    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 10,
        children: [
          Text(_overallSentence(l10n, result.verdict), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          ..._recommendedFix(context, l10n, result),
          Button.outline(
            key: const ValueKey('network-run-again'),
            onPressed: _start,
            child: Text(l10n.networkTroubleshootRunAgain),
          ),
        ],
      ),
    );
  }

  String _overallSentence(AppLocalizations l10n, NetworkVerdict verdict) {
    return switch (verdict) {
      NetworkVerdict.pass => l10n.networkOverallPass,
      NetworkVerdict.warn => l10n.networkOverallWarn,
      NetworkVerdict.fail => l10n.networkOverallFail,
      NetworkVerdict.unknown => l10n.networkOverallUnknown,
      // overallVerdict() ignores skipped rows entirely and falls back to
      // pass, so this branch is unreachable as an actual overall verdict —
      // kept only so the switch stays exhaustive.
      NetworkVerdict.skipped => l10n.networkOverallPass,
    };
  }

  /// The fixes of the first `fail` check (else the first `warn` check), as
  /// up to two buttons — the first `Button.primary`, the rest
  /// `Button.outline`. Empty when nothing failed or warned, or the row that
  /// did carries no fix.
  List<Widget> _recommendedFix(BuildContext context, AppLocalizations l10n, NetworkSelfTestResult result) {
    final target =
        result.checks.firstOrNullWhere((c) => c.verdict == NetworkVerdict.fail) ??
        result.checks.firstOrNullWhere((c) => c.verdict == NetworkVerdict.warn);
    final fixes = target?.fixes.take(2).toList() ?? const <NetworkFixId>[];
    if (fixes.isEmpty) {
      return const [];
    }
    return [
      Text(l10n.networkTroubleshootRecommendedFix, style: const TextStyle(fontWeight: FontWeight.w600)),
      Wrap(
        spacing: 8,
        children: [
          for (var i = 0; i < fixes.length; i++)
            i == 0
                ? Button.primary(
                    key: const ValueKey('network-recommended-fix'),
                    onPressed: _fixDisabled(fixes[i]) ? null : () => _runFix(fixes[i]),
                    child: Text(networkFixLabel(context, fixes[i])),
                  )
                : Button.outline(
                    onPressed: _fixDisabled(fixes[i]) ? null : () => _runFix(fixes[i]),
                    child: Text(networkFixLabel(context, fixes[i])),
                  ),
        ],
      ),
    ];
  }

  List<Widget> _checkRows(NetworkSelfTestState state) {
    final rows = <Widget>[
      for (final check in state.checks)
        if (check.verdict != NetworkVerdict.skipped) NetworkCheckRow(key: ValueKey('check-${check.id.name}'), check: check, onFix: _runFix),
    ];
    final running = state.running;
    if (running != null) {
      rows.add(
        NetworkCheckRow(
          key: ValueKey('check-${running.name}-running'),
          check: NetworkCheck(id: running, verdict: NetworkVerdict.unknown, detail: {'app': core.settings.getTrainerApp()?.name ?? ''}),
          running: true,
          watch: state.watch,
          onSkipWatch: _engine?.cancelWatch,
        ),
      );
    }
    return rows;
  }

  Widget _footer(BuildContext context, AppLocalizations l10n, NetworkSelfTestResult result) {
    return Wrap(
      spacing: 8,
      children: [
        Button.outline(
          key: const ValueKey('network-copy'),
          onPressed: () {
            Clipboard.setData(ClipboardData(text: result.toBundleString()));
            buildToast(title: l10n.networkTroubleshootResultsCopied);
          },
          child: Text(l10n.networkTroubleshootCopyResults),
        ),
        Button.outline(
          onPressed: () => _openSupport(context, result),
          child: Text(l10n.networkTroubleshootSendToSupport),
        ),
        Button.ghost(
          onPressed: () => context.push(const LogViewer()),
          child: Text(l10n.logs),
        ),
      ],
    );
  }
}
