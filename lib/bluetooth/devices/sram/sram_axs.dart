import 'dart:async';

import 'package:bike_control/bluetooth/messages/notification.dart';
import 'package:bike_control/utils/core.dart';
import 'package:bike_control/utils/i18n_extension.dart';
import 'package:bike_control/utils/keymap/buttons.dart';
import 'package:dartx/dartx.dart';
import 'package:flutter/foundation.dart';
// The prop package exports a `SramAxs` constants class with the same name as
// this file's `SramAxs` device class. Hide it from the wildcard import and
// pull it back in under a prefix so both symbols stay unambiguous.
import 'package:prop/prop.dart' hide SramAxs;
import 'package:prop/prop.dart' as sram_proto show SramAxs;
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:universal_ble/universal_ble.dart';

import '../bluetooth_device.dart';
import 'sram_ble_transport.dart';

class SramAxs extends BluetoothDevice {
  SramAxs(super.scanResult) : super(availableButtons: [], isBeta: true, supportsLongPress: false);

  SramBleTransport? _transport;
  SramAxsLogic? _logic;

  /// Logged once per connection when a press can't be decoded, so it's clear
  /// from the logs whether the session key is active this session.
  bool _loggedDegradedPress = false;

  /// Multishift/hold guard (protocol §7): while the paddle is held, the
  /// derailleur emits a rapid burst of triggers. We forward the first two (so a
  /// genuine double-click still reaches the base device) and drop the 3rd+ rapid
  /// trigger — otherwise a hold spams presses in a runaway loop.
  DateTime? _lastTriggerAt;
  int _rapidTriggerCount = 0;
  static const Duration _multishiftWindow = Duration(milliseconds: 350);

  /// Stable "Shifter A/B/..." labels assigned to controller serials in the
  /// order they are first seen.
  final List<int> _serialOrder = [];

  String get _serialKey => device.deviceId;

  String _shifterLabel(int? serial) {
    if (serial == null) return '';
    var idx = _serialOrder.indexOf(serial);
    if (idx == -1) {
      _serialOrder.add(serial);
      idx = _serialOrder.length - 1;
    }
    return String.fromCharCode('A'.codeUnitAt(0) + idx);
  }

  /// Look up a pressing shifter's advertised type/model by serial. Prefers a
  /// live scan advert (which it also persists for future sessions); falls back
  /// to the persisted (deviceType, model) so a button's §6.4 name stays stable
  /// once the shifter's advert has been seen at least once.
  SramDeviceInfo? _shifterInfo(int? serial) {
    if (serial == null) return null;
    for (final info in core.connection.sramShifterAdverts) {
      if (info.serial == serial) {
        core.settings.setSramShifter(_serialKey, serial, info.deviceType, info.model); // remember for later sessions
        return info;
      }
    }
    final stored = core.settings.getSramShifter(_serialKey, serial);
    if (stored != null) {
      return SramDeviceInfo(serial: serial, deviceType: stored.deviceType, model: stored.model);
    }
    return null;
  }

  /// Pure naming from an (optional) advert + serial + mask. Exposed for tests.
  String buttonNameFor(SramDeviceInfo? info, int? serial, int? mask) {
    if (serial == null && mask == null) return 'SRAM Button';
    final side = _sideLabel(info, serial); // 'Left'/'Right' (type 0/1), else 'Shifter A/B', else ''
    if (mask == null) return side.isEmpty ? 'SRAM Button' : 'SRAM $side';
    final role = SramShifterButtons.nameFor(info?.deviceType, info?.model, mask);
    // Some roles already encode the side (drop-bar "Left/Right Shifter", "Vuka L/R
    // Shifter") — don't prefix a redundant side.
    if (role.startsWith('Left ') || role.startsWith('Right ') || role.startsWith('Vuka ')) return 'SRAM $role';
    return side.isEmpty ? 'SRAM $role' : 'SRAM $side – $role';
  }

  /// Stable name for one physical (shifter, button). Single vs double click is
  /// handled by the base device from the keymap, not encoded in the name.
  String logicalButtonName(int? serial, int? mask) => buttonNameFor(_shifterInfo(serial), serial, mask);

  String _sideLabel(SramDeviceInfo? info, int? serial) {
    if (info?.deviceType == 0) return 'Left';
    if (info?.deviceType == 1) return 'Right';
    if (serial != null) return 'Shifter ${_shifterLabel(serial)}';
    return '';
  }

  // -1 is the persisted sentinel for "null" (see Settings.addSramButton).
  static int? _fromStored(int v) => v == -1 ? null : v;

  /// Names a persisted (stored) button, mapping the `-1` sentinel back to null
  /// so re-registration never yields `"Button 0x-1"` or a phantom shifter slot.
  /// Exposed for tests.
  String storedButtonName(int storedSerial, int storedMask) =>
      logicalButtonName(_fromStored(storedSerial), _fromStored(storedMask));

  @override
  Future<void> handleServices(List<BleService> services) async {
    final transport = SramBleTransport(device.deviceId, services);
    final logic = SramAxsLogic(transport);
    _transport = transport;
    _logic = logic;

    // Seed a previously-persisted session key so we start bonded when possible.
    final storedKey = core.settings.getSramKey(_serialKey);
    if (storedKey != null) {
      logic.seedKey(_hexToBytes(storedKey));
    }

    // Subscribe: press trigger, component event (plaintext), bond channel.
    for (final char in [sram_proto.SramAxs.controlTriggerChar, sram_proto.SramAxs.componentEventChar, sram_proto.SramAxs.bondChar]) {
      final service = services.firstOrNullWhere((s) => s.characteristics.any((c) => c.uuid == char.toLowerCase()));
      if (service != null) {
        await UniversalBle.subscribeNotifications(device.deviceId, service.uuid, char.toLowerCase());
      } else if (char == sram_proto.SramAxs.controlTriggerChar) {
        // The trigger char is essential; without it the device can't report
        // presses. Log it so a non-functional connect is diagnosable from logs.
        actionStreamInternal.add(LogNotification('SramAxs: control-trigger characteristic $char not found'));
      }
    }

    // Re-register any previously-discovered buttons so they persist in the keymap.
    // The `-1` sentinel is mapped back to null so it never yields "Button 0x-1".
    for (final b in core.settings.getSramButtons(_serialKey)) {
      _registerButton(_fromStored(b.serial), _fromStored(b.mask));
    }

    // Pre-register buttons for nearby SRAM shifters (§6.4) so they show up in the
    // keymap without needing a press. Persist each advert (serial → type/model)
    // so its buttons keep the same §6.4 name in future sessions even when the
    // shifter isn't advertising.
    for (final info in core.connection.sramShifterAdverts) {
      core.settings.setSramShifter(_serialKey, info.serial, info.deviceType, info.model);
      for (final mask in SramShifterButtons.masksFor(info.deviceType, info.model)) {
        final name = buttonNameFor(info, info.serial, mask);
        getOrAddButton(name, () => ControllerButton(name, action: InGameAction.shiftUp, sourceDeviceId: device.deviceId));
      }
    }
  }

  ControllerButton _registerButton(int? serial, int? mask) {
    final name = logicalButtonName(serial, mask);
    return getOrAddButton(name, () => ControllerButton(name, action: InGameAction.shiftUp, sourceDeviceId: device.deviceId));
  }

  @override
  Future<void> processCharacteristic(String characteristic, Uint8List bytes) async {
    final lc = characteristic.toLowerCase();
    _transport?.onNotification(characteristic, bytes);

    if (lc == sram_proto.SramAxs.componentEventChar.toLowerCase()) {
      _logic?.onComponentEvent(bytes);
      return;
    }

    if (lc == sram_proto.SramAxs.controlTriggerChar.toLowerCase()) {
      // Only the 1-byte 0xFF edge is a press (§6.1). handleTrigger() READS the
      // encrypted button event from this same characteristic; on iOS/CoreBluetooth
      // a read response is also delivered through the notify callback, so that
      // multi-byte value re-enters here — treating it as a new press would read
      // again and spin an infinite loop. Ignore anything that isn't the 0xFF edge.
      if (bytes.length != 1 || bytes[0] != 0xFF) return;

      // Multishift/hold guard (§7): a held paddle makes the derailleur emit a
      // rapid burst of triggers. Forward the first two (a real double-click
      // still reaches the base device) and drop the 3rd+ rapid one so a hold
      // doesn't spam presses in a loop.
      final now = DateTime.now();
      final rapid = _lastTriggerAt != null && now.difference(_lastTriggerAt!) < _multishiftWindow;
      _lastTriggerAt = now;
      _rapidTriggerCount = rapid ? _rapidTriggerCount + 1 : 0;
      if (_rapidTriggerCount >= 2) return;

      // 0xFF edge → resolve identity (may read+decrypt), then emit a single
      // physical press. Single vs double click is handled by the base device.
      final press = await _logic?.handleTrigger() ?? const SramPress();
      // Persist a re-bond if the key was just dropped.
      if (_logic != null && !_logic!.isBonded && core.settings.getSramKey(_serialKey) != null) {
        await core.settings.setSramKey(_serialKey, null);
      }
      final serial = press.controllerSerial;
      final mask = press.buttonMask;
      if (mask == null && !_loggedDegradedPress) {
        _loggedDegradedPress = true;
        actionStreamInternal.add(
          LogNotification(
            'SramAxs: press received but not decoded — the bond session key is not active this '
            'session (using plaintext). Full per-button decoding and setup/restore need '
            're-authorizing (Set up SRAM control → press and hold the AXS button).',
          ),
        );
      }
      if (serial != null || mask != null) {
        await core.settings.addSramButton(_serialKey, serial ?? -1, mask ?? -1);
      }
      final button = _registerButton(serial, mask);
      await handleButtonsClicked([button]);
      await handleButtonsClicked([]);
    }
  }

  Uint8List _hexToBytes(String hex) => Uint8List.fromList([
        for (var i = 0; i < hex.length; i += 2) int.parse(hex.substring(i, i + 2), radix: 16),
      ]);

  String _bytesToHex(Uint8List b) => b.map((e) => e.toRadixString(16).padLeft(2, '0')).join();

  // ── Guided setup / restore (called from the UI in Task 12) ────────────────

  Future<void> setupControl() async {
    final logic = _logic;
    if (logic == null) return;
    try {
      // Ensure a working bond (re-bonds if a persisted key went stale).
      await logic.ensureBonded();
      await core.settings.setSramKey(_serialKey, _bytesToHex(logic.sessionKey!));
      // Capture the ORIGINAL config exactly once. Never overwrite a saved backup:
      // a re-run (or a mid-unassign failure retry) reads the already-cleared
      // device and would otherwise wipe the only copy of the user's config.
      if (core.settings.getSramBackup(_serialKey) == null) {
        final backup = await logic.backupConfig();
        await core.settings.setSramBackup(_serialKey, backup);
      }
      await logic.disableShifting();
      await core.settings.setSramShiftingDisabled(_serialKey, true);
      core.connection.signalChange(this);
    } catch (e, st) {
      actionStreamInternal.add(LogNotification('SramAxs setup failed: $e\n$st'));
      rethrow;
    }
  }

  Future<void> restoreShifting() async {
    final logic = _logic;
    final backup = core.settings.getSramBackup(_serialKey);
    if (logic == null || backup == null) return;
    try {
      await logic.restoreConfig(backup);
      await core.settings.setSramKey(_serialKey, _bytesToHex(logic.sessionKey!)); // persist any re-bond
      await core.settings.setSramShiftingDisabled(_serialKey, false);
      await core.settings.clearSramBackup(_serialKey); // next setup captures fresh
      core.connection.signalChange(this);
    } catch (e, st) {
      actionStreamInternal.add(LogNotification('SramAxs restore failed: $e\n$st'));
      rethrow;
    }
  }

  bool get isBonded => _logic?.isBonded ?? false;
  bool get isShiftingDisabled => core.settings.getSramShiftingDisabled(_serialKey);

  @override
  List<Widget> showAdditionalInformation(BuildContext context) => [_buildSetupPanel(context)];

  // The setup panel lives on the main device card (showAdditionalInformation),
  // so there's no separate preferences view.
  @override
  Widget? buildPreferences(BuildContext context) => null;

  Widget _buildSetupPanel(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final l = context.i18n;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final hasBackup = core.settings.getSramBackup(_serialKey) != null;

    // This renders inside the device card, which already shows the device header
    // and the mappable-button list — so keep it to just the current status and
    // the setup/restore action. The rich flow lives in the guided sheet.
    if (!isShiftingDisabled) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l.sramPanelIntro,
            style: TextStyle(fontSize: 13.5, height: 1.4, color: scheme.mutedForeground),
          ),
          const Gap(12),
          SizedBox(
            width: double.infinity,
            child: PrimaryButton(
              leading: const Icon(LucideIcons.slidersHorizontal, size: 16),
              onPressed: () => unawaited(_runGuidedOperation(
                context,
                title: l.sramSetup,
                intro: l.sramSetupIntro,
                successMessage: l.sramSetupSuccess,
                confirmIcon: LucideIcons.slidersHorizontal,
                runningTitle: l.sramSettingUp,
                successTitle: l.sramAllSet,
                checklistItems: [l.sramChecklistPairing, l.sramChecklistBackingUp, l.sramChecklistDisabling],
                operation: setupControl,
              )),
              child: Text(l.sramSetup),
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: dark ? const Color(0x1A22C55E) : _sramSuccessWash,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              const Icon(LucideIcons.circleCheck, size: 18, color: _sramSuccess),
              const Gap(10),
              Expanded(
                child: Text(
                  l.sramShiftingOff,
                  style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, height: 1.35),
                ),
              ),
            ],
          ),
        ),
        if (hasBackup) ...[
          const Gap(12),
          SizedBox(
            width: double.infinity,
            child: SecondaryButton(
              leading: const Icon(LucideIcons.rotateCcw, size: 16),
              onPressed: () => unawaited(_runGuidedOperation(
                context,
                title: l.sramRestore,
                intro: l.sramRestoreIntro,
                successMessage: l.sramRestoreSuccess,
                confirmIcon: LucideIcons.rotateCcw,
                runningTitle: l.sramRestoringShifting,
                successTitle: l.sramRestoredTitle,
                checklistItems: [l.sramChecklistPairing, l.sramChecklistRestoring],
                operation: restoreShifting,
              )),
              child: Text(l.sramRestore),
            ),
          ),
        ],
      ],
    );
  }

  /// Interactive, staged runner for setup/restore, presented as a bottom sheet:
  /// guide the AXS authorize gesture, show progress, and surface any error
  /// (notably the bond-authorization failure — which happens when the session
  /// key didn't survive a reconnect and a fresh bond is needed) with a Retry.
  Future<void> _runGuidedOperation(
    BuildContext context, {
    required String title,
    required String intro,
    required String successMessage,
    required IconData confirmIcon,
    required String runningTitle,
    required String successTitle,
    required List<String> checklistItems,
    required Future<void> Function() operation,
  }) async {
    await openSheet<void>(
      context: context,
      position: OverlayPosition.bottom,
      barrierDismissible: false,
      builder: (sheetContext) => _SramGuidedSheet(
        title: title,
        intro: intro,
        successMessage: successMessage,
        confirmIcon: confirmIcon,
        runningTitle: runningTitle,
        successTitle: successTitle,
        checklistItems: checklistItems,
        operation: operation,
      ),
    );
    core.connection.signalChange(this);
  }

  // ── Test seams ────────────────────────────────────────────────────────────
  // The bottom sheet is an overlay route, which the widget-snapshot harness
  // can't capture. These expose the same per-stage content as a plain widget
  // (test == production: both go through `_sramGuidedBody`), and a way to seed
  // discovered controls into the active panel.

  // Stage handles for the snapshot harness — plain ints (indices into
  // `_SramSetupStage.values`) so no private type leaks into the public API.
  @visibleForTesting
  static const int debugStageConfirm = 0;
  @visibleForTesting
  static const int debugStageRunning = 1;
  @visibleForTesting
  static const int debugStageAuthorize = 2;
  @visibleForTesting
  static const int debugStageSuccess = 3;
  @visibleForTesting
  static const int debugStageError = 4;

  /// The exact per-stage sheet body the guided operation renders, as a
  /// standalone widget (actions are inert). [runningStep] seeds the running
  /// checklist's current index (that item spins, earlier items are done).
  @visibleForTesting
  Widget debugGuidedSheetBody(
    BuildContext context, {
    required int stage,
    required IconData confirmIcon,
    required String title,
    required String intro,
    required String successMessage,
    required String runningTitle,
    required String successTitle,
    required List<String> checklistItems,
    int runningStep = 1,
  }) =>
      _sramGuidedBody(
        context,
        stage: _SramSetupStage.values[stage],
        confirmIcon: confirmIcon,
        title: title,
        intro: intro,
        successMessage: successMessage,
        runningTitle: runningTitle,
        successTitle: successTitle,
        checklistItems: checklistItems,
        runningStep: runningStep,
        checklistAutoAdvance: false,
        onClose: () {},
        onProceed: () {},
      );
}

enum _SramSetupStage { confirm, running, authorize, success, error }

// ── SRAM setup/restore UI (design tokens + presentational widgets) ──────────

const Color _sramSuccess = Color(0xFF22C55E);
const Color _sramSuccessWash = Color(0xFFF0FDFA);
const Color _sramAmber = Color(0xFFF59E0B);
const Color _sramAmberWash = Color(0xFFFFFBEB);
const Color _sramErrorWash = Color(0xFFFEF2F2);
const Color _sramChipDark = Color(0xFF1B2430);
const Color _sramWhite = Color(0xFFFFFFFF);

/// The staged guided-operation body inside the bottom sheet. Holds the
/// stage machine (confirm → running → success | authorize | error) exactly
/// as before; only the presentation changed.
class _SramGuidedSheet extends StatefulWidget {
  final String title;
  final String intro;
  final String successMessage;
  final IconData confirmIcon;
  final String runningTitle;
  final String successTitle;
  final List<String> checklistItems;
  final Future<void> Function() operation;

  const _SramGuidedSheet({
    required this.title,
    required this.intro,
    required this.successMessage,
    required this.confirmIcon,
    required this.runningTitle,
    required this.successTitle,
    required this.checklistItems,
    required this.operation,
  });

  @override
  State<_SramGuidedSheet> createState() => _SramGuidedSheetState();
}

class _SramGuidedSheetState extends State<_SramGuidedSheet> {
  var _stage = _SramSetupStage.confirm;

  Future<void> _attempt() async {
    setState(() => _stage = _SramSetupStage.running);
    try {
      await widget.operation();
      if (!mounted) return;
      setState(() => _stage = _SramSetupStage.success);
    } on SramBondException {
      // A fresh bond is needed (no valid key). Only NOW do we ask the user to
      // authorize — when already bonded this never shows.
      if (!mounted) return;
      setState(() => _stage = _SramSetupStage.authorize);
    } catch (_) {
      if (!mounted) return;
      setState(() => _stage = _SramSetupStage.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(left: 20, right: 20, top: 8, bottom: 20 + MediaQuery.of(context).viewInsets.bottom),
        child: _sramGuidedBody(
          context,
          stage: _stage,
          confirmIcon: widget.confirmIcon,
          title: widget.title,
          intro: widget.intro,
          successMessage: widget.successMessage,
          runningTitle: widget.runningTitle,
          successTitle: widget.successTitle,
          checklistItems: widget.checklistItems,
          onClose: () => closeSheet(context),
          onProceed: _attempt,
        ),
      ),
    );
  }
}

/// Builds the per-stage guided-operation content (step rail, icon badge, title,
/// body, checklist / AXS hero, actions). Shared by the live bottom sheet and the
/// snapshot harness so what tests capture is exactly what ships. [onProceed]
/// drives Continue/Retry; [onClose] drives Cancel/Done.
Widget _sramGuidedBody(
  BuildContext context, {
  required _SramSetupStage stage,
  required IconData confirmIcon,
  required String title,
  required String intro,
  required String successMessage,
  required String runningTitle,
  required String successTitle,
  required List<String> checklistItems,
  required VoidCallback onClose,
  required VoidCallback onProceed,
  int runningStep = 0,
  bool checklistAutoAdvance = true,
}) {
  final scheme = Theme.of(context).colorScheme;
  final l = context.i18n;
  final dark = Theme.of(context).brightness == Brightness.dark;
  final reduceMotion = MediaQuery.of(context).disableAnimations;

  final IconData icon;
  final Color tone;
  final Color wash;
  final String heading;
  final String body;
  final List<Widget> actions;
  final Widget? extra;
  final int? stepIndex; // 1-based step of 2; null → no rail

  switch (stage) {
    case _SramSetupStage.confirm:
      icon = confirmIcon;
      tone = scheme.primary;
      wash = scheme.primary.withValues(alpha: 0.1);
      heading = title;
      body = intro;
      stepIndex = 1;
      extra = null;
      actions = [
        GhostButton(onPressed: onClose, child: Text(l.cancel)),
        PrimaryButton(
          trailing: const Icon(LucideIcons.arrowRight, size: 16),
          onPressed: onProceed,
          child: Text(l.continueAction),
        ),
      ];
    case _SramSetupStage.running:
      icon = LucideIcons.radio;
      tone = scheme.primary;
      wash = scheme.primary.withValues(alpha: 0.1);
      heading = runningTitle;
      body = l.sramDialogRunning;
      stepIndex = 2;
      extra = _SramChecklist(
        items: checklistItems,
        reduceMotion: reduceMotion,
        initialStep: runningStep,
        autoAdvance: checklistAutoAdvance,
      );
      actions = const [];
    case _SramSetupStage.authorize:
      icon = LucideIcons.keyRound;
      tone = _sramAmber;
      wash = dark ? const Color(0x1AF59E0B) : _sramAmberWash;
      heading = l.sramAuthorizeTitle;
      body = l.sramAuthorizeBody;
      stepIndex = null;
      extra = _SramAxsHero(reduceMotion: reduceMotion);
      actions = [
        GhostButton(onPressed: onClose, child: Text(l.cancel)),
        PrimaryButton(
          leading: const Icon(LucideIcons.rotateCw, size: 16),
          onPressed: onProceed,
          child: Text(l.retry),
        ),
      ];
    case _SramSetupStage.success:
      icon = LucideIcons.circleCheck;
      tone = _sramSuccess;
      wash = dark ? const Color(0x1A22C55E) : _sramSuccessWash;
      heading = successTitle;
      body = successMessage;
      stepIndex = null;
      extra = null;
      actions = [
        PrimaryButton(onPressed: onClose, child: Text(l.done)),
      ];
    case _SramSetupStage.error:
      icon = LucideIcons.triangleAlert;
      tone = scheme.destructive;
      wash = dark ? const Color(0x1AEF4444) : _sramErrorWash;
      heading = l.sramErrorTitle;
      body = l.sramGenericError;
      stepIndex = null;
      extra = null;
      actions = [
        GhostButton(onPressed: onClose, child: Text(l.cancel)),
        PrimaryButton(
          leading: const Icon(LucideIcons.rotateCw, size: 16),
          onPressed: onProceed,
          child: Text(l.retry),
        ),
      ];
  }

  return Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (stepIndex != null) ...[
        _SramStepRail(step: stepIndex),
        const Gap(18),
      ],
      Center(child: _SramStageBadge(icon: icon, tone: tone, wash: wash, reduceMotion: reduceMotion)),
      const Gap(16),
      Text(
        heading,
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w700),
      ),
      const Gap(8),
      Text(
        body,
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 14.5, height: 1.5, color: scheme.mutedForeground),
      ),
      if (extra != null) ...[
        const Gap(20),
        extra,
      ],
      const Gap(24),
      Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          for (final (i, action) in actions.indexed) ...[
            if (i > 0) const Gap(8),
            action,
          ],
        ],
      ),
    ],
  );
}

/// STEP-of-2 progress dots. Text ("STEP n OF 2") is intentionally omitted —
/// there is no l10n key for it and copy must be localized — so the current
/// step reads as the widened brand dot.
class _SramStepRail extends StatelessWidget {
  final int step;
  const _SramStepRail({required this.step});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 1; i <= 2; i++) ...[
          if (i > 1) const Gap(6),
          Container(
            width: i == step ? 18 : 7,
            height: 7,
            decoration: BoxDecoration(
              color: i == step ? scheme.primary : scheme.border,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ],
      ],
    );
  }
}

/// 58px tone-washed icon badge with a pop-in (skipped under reduced motion).
class _SramStageBadge extends StatelessWidget {
  final IconData icon;
  final Color tone;
  final Color wash;
  final bool reduceMotion;
  const _SramStageBadge({required this.icon, required this.tone, required this.wash, required this.reduceMotion});

  @override
  Widget build(BuildContext context) {
    final badge = Container(
      width: 58,
      height: 58,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: wash, shape: BoxShape.circle),
      child: Icon(icon, size: 28, color: tone),
    );
    if (reduceMotion) return badge;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.6, end: 1.0),
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutBack,
      builder: (context, scale, child) => Transform.scale(scale: scale, child: child),
      child: badge,
    );
  }
}

/// Running-stage checklist. A cosmetic timer advances the "current" row every
/// ~650ms; the real transition is the stage change. Under reduced motion the
/// timer and spinner are skipped (a static in-progress marker is shown).
class _SramChecklist extends StatefulWidget {
  final List<String> items;
  final bool reduceMotion;
  final int initialStep;
  final bool autoAdvance;
  const _SramChecklist({
    required this.items,
    required this.reduceMotion,
    this.initialStep = 0,
    this.autoAdvance = true,
  });

  @override
  State<_SramChecklist> createState() => _SramChecklistState();
}

class _SramChecklistState extends State<_SramChecklist> {
  late int _current = widget.initialStep;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    if (widget.autoAdvance && !widget.reduceMotion) {
      _timer = Timer.periodic(const Duration(milliseconds: 650), (t) {
        if (!mounted) return;
        if (_current >= widget.items.length - 1) {
          t.cancel();
          return;
        }
        setState(() => _current++);
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < widget.items.length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                _marker(i, scheme),
                const Gap(12),
                Expanded(
                  child: Text(
                    widget.items[i],
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: i > _current ? scheme.mutedForeground.withValues(alpha: 0.4) : scheme.foreground,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _marker(int i, ColorScheme scheme) {
    const double d = 20;
    if (i < _current) {
      return Container(
        width: d,
        height: d,
        alignment: Alignment.center,
        decoration: const BoxDecoration(color: _sramSuccess, shape: BoxShape.circle),
        child: const Icon(LucideIcons.check, size: 12, color: _sramWhite),
      );
    }
    if (i == _current) {
      if (widget.reduceMotion) {
        return Container(
          width: d,
          height: d,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: scheme.primary, width: 2.5),
          ),
        );
      }
      return SizedBox(
        width: d,
        height: d,
        child: CircularProgressIndicator(size: d, strokeWidth: 2.5, color: scheme.primary),
      );
    }
    return Container(
      width: d,
      height: d,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: scheme.border, width: 2),
      ),
    );
  }
}

/// Authorize-stage hero: an AXS chip inside two amber rings that pulse outward,
/// with a blinking LED, over a "press & hold" pill. All motion is skipped under
/// reduced motion (final resting state shown).
class _SramAxsHero extends StatefulWidget {
  final bool reduceMotion;
  const _SramAxsHero({required this.reduceMotion});

  @override
  State<_SramAxsHero> createState() => _SramAxsHeroState();
}

class _SramAxsHeroState extends State<_SramAxsHero> with TickerProviderStateMixin {
  AnimationController? _pulse;
  AnimationController? _blink;

  @override
  void initState() {
    super.initState();
    if (!widget.reduceMotion) {
      _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 1800))..repeat();
      _blink = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _pulse?.dispose();
    _blink?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      children: [
        SizedBox(
          width: 108,
          height: 108,
          child: Stack(
            alignment: Alignment.center,
            children: [
              if (_pulse != null) ...[
                _ring(0.0),
                _ring(0.5),
              ],
              _chip(),
            ],
          ),
        ),
        const Gap(16),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: ShapeDecoration(
            color: dark ? const Color(0x1AF59E0B) : _sramAmberWash,
            shape: const StadiumBorder(),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(LucideIcons.hand, size: 15, color: _sramAmber),
              const Gap(8),
              Flexible(
                child: Text(
                  context.i18n.sramPressHold,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _sramAmber),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _ring(double phase) {
    return AnimatedBuilder(
      animation: _pulse!,
      builder: (context, _) {
        final t = (_pulse!.value + phase) % 1.0;
        final scale = 0.82 + (1.25 - 0.82) * t;
        final opacity = (0.7 * (1 - t)).clamp(0.0, 0.7);
        return Transform.scale(
          scale: scale,
          child: Container(
            width: 84,
            height: 84,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: _sramAmber.withValues(alpha: opacity), width: 2),
            ),
          ),
        );
      },
    );
  }

  Widget _chip() {
    return Container(
      width: 84,
      height: 84,
      alignment: Alignment.center,
      decoration: const BoxDecoration(color: _sramChipDark, shape: BoxShape.circle),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_blink != null)
            AnimatedBuilder(
              animation: _blink!,
              builder: (context, _) => _led(0.35 + 0.65 * _blink!.value),
            )
          else
            _led(1.0),
          const Gap(7),
          const Text(
            'AXS',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: _sramWhite, letterSpacing: 1.4),
          ),
        ],
      ),
    );
  }

  Widget _led(double opacity) => Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(
          color: _sramAmber.withValues(alpha: opacity),
          shape: BoxShape.circle,
          boxShadow: [BoxShadow(color: _sramAmber.withValues(alpha: opacity * 0.6), blurRadius: 6)],
        ),
      );
}

class SramAxsConstants {
  static const String SERVICE_UUID = "0000fe51-0000-1000-8000-00805f9b34fb";
  static const String SERVICE_UUID_RELEVANT = "d9050053-90aa-4c7c-b036-1e01fb8eb7ee";

  static const String TRIGGER_UUID = "d9050054-90aa-4c7c-b036-1e01fb8eb7ee";
}
