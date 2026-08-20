import 'dart:async';

import 'package:bike_control/bluetooth/devices/proxy/proxy_device.dart';
import 'package:bike_control/gen/l10n.dart';
import 'package:bike_control/main.dart' show recordError;
import 'package:bike_control/services/trainer_self_test/self_test_engine.dart';
import 'package:bike_control/services/trainer_self_test/self_test_harness.dart';
import 'package:bike_control/services/trainer_self_test/self_test_result.dart';
import 'package:bike_control/utils/core.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

/// Why a start tap was turned down. Both are states the rider can fix in a few
/// seconds, so they are shown inline on the card instead of as a toast.
enum _Refusal { disconnected, trainerApp }

/// Guided "does this trainer actually obey us?" test on the trainer page.
///
/// Owns everything around [SelfTestEngine] that the engine deliberately does
/// not: the prechecks, the screen wakelock, persisting the verdict per trainer
/// and the three visual states (idle → running → verdict).
class SelfTestCard extends StatefulWidget {
  final ProxyDevice device;

  /// Test seam: builds the engine; defaults to [SelfTestEngine] over a
  /// [FitnessBikeHarness] for [device].
  final SelfTestEngine Function()? engineFactory;

  /// Wired by the page to its overlay-section reveal; used by the PASS CTA.
  final VoidCallback? onShowOverlaySettings;

  const SelfTestCard({super.key, required this.device, this.engineFactory, this.onShowOverlaySettings});

  @override
  State<SelfTestCard> createState() => _SelfTestCardState();
}

class _SelfTestCardState extends State<SelfTestCard> {
  /// Non-null from the moment a run starts. [SelfTestEngine.run] is
  /// single-shot, so "Run again" builds a fresh one rather than reusing this.
  SelfTestEngine? _engine;
  _Refusal? _refusal;

  @override
  void dispose() {
    // A run outlives the page unless we stop it: the engine would keep writing
    // ERG targets and gears at a trainer nobody is watching.
    _engine?.cancel();
    _wakelock(false);
    super.dispose();
  }

  Future<void> _start() async {
    // Prechecks read the device, not the harness: with no upstream link there
    // is no harness worth building, and the trainer-app check is about who owns
    // the trainer right now — both live on ProxyDevice.
    if (!widget.device.isConnected) {
      setState(() => _refusal = _Refusal.disconnected);
      return;
    }
    if (widget.device.isConnectedListenable.value) {
      setState(() => _refusal = _Refusal.trainerApp);
      return;
    }
    final engine = _buildEngine();
    if (engine == null) {
      return;
    }
    setState(() {
      _refusal = null;
      _engine = engine;
    });
    _wakelock(true);
    try {
      final result = await engine.run();
      // An aborted run measured nothing — persisting it would put "Test
      // stopped" in the support bundle in place of the last real verdict.
      if (result.verdict != SelfTestVerdict.aborted) {
        await core.settings.setSelfTestResultJson(widget.device.trainerKey, result.toJsonString());
      }
    } catch (e, s) {
      recordError(e, s, context: 'self-test card run');
      // Back to idle rather than stranding the rider on a "running" card that
      // will never reach a verdict.
      if (mounted) {
        setState(() => _engine = null);
      }
    } finally {
      _wakelock(false);
    }
  }

  SelfTestEngine? _buildEngine() {
    final factory = widget.engineFactory;
    if (factory != null) {
      return factory();
    }
    // FitnessBikeHarness dereferences device.fitnessBike; the page only shows
    // the card when that is non-null, but a rebuild can race a disconnect.
    return widget.device.fitnessBike == null ? null : SelfTestEngine(harness: FitnessBikeHarness(widget.device));
  }

  /// Keeps the screen awake for the ~1 minute the rider has to keep pedaling.
  /// Fire-and-forget like the mini-workout recorder, but a refused toggle is
  /// reported instead of surfacing as an unhandled async error.
  void _wakelock(bool enable) {
    unawaited(
      WakelockPlus.toggle(
        enable: enable,
      ).catchError((Object e, StackTrace s) => recordError(e, s, context: 'self-test wakelock')),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.engineFactory == null && widget.device.fitnessBike == null) {
      return const SizedBox.shrink();
    }
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.card,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: cs.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 12,
        children: [
          Row(
            spacing: 8,
            children: [
              const Icon(LucideIcons.gauge, size: 18),
              Text(l10n.selfTestTitle, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            ],
          ),
          _body(context, l10n),
        ],
      ),
    );
  }

  Widget _body(BuildContext context, AppLocalizations l10n) {
    final engine = _engine;
    if (engine == null) {
      return _idle(context, l10n);
    }
    return ValueListenableBuilder<SelfTestState>(
      valueListenable: engine.state,
      builder: (context, state, _) {
        final result = state.result;
        if (result != null) {
          return _verdict(context, l10n, result);
        }
        return _running(context, l10n, engine, state);
      },
    );
  }

  Widget _idle(BuildContext context, AppLocalizations l10n) {
    final cs = Theme.of(context).colorScheme;
    final last = SelfTestResult.tryParse(core.settings.getSelfTestResultJson(widget.device.trainerKey));
    final refusal = _refusal;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 10,
      children: [
        Text(l10n.selfTestIntro, style: TextStyle(fontSize: 13, color: cs.mutedForeground)),
        if (last != null)
          Align(
            alignment: Alignment.centerLeft,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 10),
              decoration: BoxDecoration(color: cs.muted, borderRadius: BorderRadius.circular(999)),
              child: Text(
                l10n.selfTestLastResult(_verdictTitle(l10n, last.verdict)),
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: cs.mutedForeground),
              ),
            ),
          ),
        if (refusal != null)
          _notice(
            context,
            icon: LucideIcons.triangleAlert,
            message: switch (refusal) {
              _Refusal.disconnected => l10n.selfTestPrecheckDisconnected,
              _Refusal.trainerApp => l10n.selfTestPrecheckTrainerApp,
            },
            color: cs.destructive,
          ),
        Button.primary(onPressed: _start, child: Text(l10n.selfTestStart)),
      ],
    );
  }

  Widget _running(BuildContext context, AppLocalizations l10n, SelfTestEngine engine, SelfTestState state) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 10,
      children: [
        Text(
          _phaseLabel(l10n, state.phase),
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
        ValueListenableBuilder<int?>(
          valueListenable: engine.harness.powerW,
          // Live power is the one signal that tells the rider the test is
          // watching them — and, during the staircase, what it is aiming at.
          builder: (context, power, _) => Text(
            '${power ?? '--'} W${state.currentErgTarget == null ? '' : ' → ${state.currentErgTarget} W'}',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w700, letterSpacing: -0.5),
          ),
        ),
        Text(
          l10n.selfTestPedalPrompt,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, color: cs.mutedForeground),
        ),
        if (state.pausedForCadence)
          _notice(context, icon: LucideIcons.rotateCw, message: l10n.selfTestKeepPedaling, color: cs.destructive),
        Button.outline(onPressed: engine.cancel, child: Text(l10n.selfTestCancel)),
      ],
    );
  }

  /// Title + rerun only — the verdict bodies and their CTAs are wired next.
  Widget _verdict(BuildContext context, AppLocalizations l10n, SelfTestResult result) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 10,
      children: [
        Text(
          _verdictTitle(l10n, result.verdict),
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
        Button.primary(onPressed: _start, child: Text(l10n.selfTestRerun)),
      ],
    );
  }

  Widget _notice(BuildContext context, {required IconData icon, required String message, required Color color}) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
      decoration: BoxDecoration(
        color: cs.muted,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 8,
        children: [
          Icon(icon, size: 15, color: color),
          Expanded(
            child: Text(message, style: TextStyle(fontSize: 12, color: color)),
          ),
        ],
      ),
    );
  }

  /// [SelfTestPhase.idle] only shows in the frame between the start tap and the
  /// engine's first emit, and [SelfTestPhase.done] never reaches here (a done
  /// state always carries a result), so both fall back to the opening phase.
  static String _phaseLabel(AppLocalizations l10n, SelfTestPhase phase) {
    return switch (phase) {
      SelfTestPhase.ergStaircase => l10n.selfTestPhaseErg,
      SelfTestPhase.shiftSweep => l10n.selfTestPhaseShift,
      _ => l10n.selfTestPhaseBaseline,
    };
  }

  static String _verdictTitle(AppLocalizations l10n, SelfTestVerdict verdict) {
    return switch (verdict) {
      SelfTestVerdict.pass => l10n.selfTestVerdictPassTitle,
      SelfTestVerdict.ergOkVsFail => l10n.selfTestVerdictErgOkTitle,
      SelfTestVerdict.noControl => l10n.selfTestVerdictNoControlTitle,
      SelfTestVerdict.noData => l10n.selfTestVerdictNoDataTitle,
      SelfTestVerdict.aborted => l10n.selfTestVerdictAbortedTitle,
    };
  }
}
