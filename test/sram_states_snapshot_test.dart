@Tags(['screenshots'])
library;

import 'package:bike_control/bluetooth/devices/sram/sram_axs.dart';
import 'package:bike_control/utils/core.dart' show core;
import 'package:bike_control/utils/i18n_extension.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prop/prop.dart' hide SramAxs;
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:universal_ble/universal_ble.dart';

import 'widget_snapshot.dart';

/// Renders every SRAM AXS device UI state to a PNG for UX review.
///
/// Output: `build/snapshots/sram_*-<locale>.png`.
/// Run: `flutter test --run-skipped test/sram_states_snapshot_test.dart`
/// (run on its own — do not co-run with integration tests: app_links poison.)
///
/// The guided setup/restore flow is a bottom-sheet overlay route, which this
/// widget-snapshot harness can't capture directly. Instead each stage's body is
/// rendered via [SramAxs.debugGuidedSheetBody] — the very same builder the live
/// sheet uses — so what's captured here is exactly what ships.
Future<void> main() async {
  await ensureSnapshotHarness();

  const locales = ['en', 'de'];
  const key = 'sram-snap';
  final device = SramAxs(BleDevice(deviceId: key, name: 'SRAM Rival AXS'));

  Widget panel(BuildContext context) => Card(child: Column(children: device.showAdditionalInformation(context)));

  // Wrap a stage body so it reads like the bottom sheet (surface + padding).
  Widget sheet(Widget body) => Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: body,
        ),
      );

  // The exact params the panel's setup / restore buttons pass to the sheet.
  Widget setupBody(BuildContext c, int stage, {int runningStep = 1}) => sheet(device.debugGuidedSheetBody(
        c,
        stage: stage,
        confirmIcon: LucideIcons.slidersHorizontal,
        title: c.i18n.sramSetup,
        intro: c.i18n.sramSetupIntro,
        successMessage: c.i18n.sramSetupSuccess,
        runningTitle: c.i18n.sramSettingUp,
        successTitle: c.i18n.sramAllSet,
        checklistItems: [c.i18n.sramChecklistPairing, c.i18n.sramChecklistBackingUp, c.i18n.sramChecklistDisabling],
        runningStep: runningStep,
      ));

  Widget restoreBody(BuildContext c, int stage) => sheet(device.debugGuidedSheetBody(
        c,
        stage: stage,
        confirmIcon: LucideIcons.rotateCcw,
        title: c.i18n.sramRestore,
        intro: c.i18n.sramRestoreIntro,
        successMessage: c.i18n.sramRestoreSuccess,
        runningTitle: c.i18n.sramRestoringShifting,
        successTitle: c.i18n.sramRestoredTitle,
        checklistItems: [c.i18n.sramChecklistPairing, c.i18n.sramChecklistRestoring],
      ));

  // ── Panel states ─────────────────────────────────────────────────────────
  testWidgets('panel — not yet set up', (tester) async {
    await core.settings.setSramShiftingDisabled(key, false);
    await core.settings.clearSramBackup(key);
    // The unconfigured panel is just the intro + "Set up SRAM control" button.
    await captureWidget(tester, name: 'sram_panel_setup', width: 380, locales: locales, builder: panel);
  });

  testWidgets('panel — shifting disabled (restore available)', (tester) async {
    await core.settings.setSramShiftingDisabled(key, true);
    await core.settings.setSramBackup(key, {
      'd9050028-90aa-4c7c-b036-1e01fb8eb7ee': const SramReactionTrigger([0], [1]),
    });
    // The panel is now just status + restore — the discovered controls live in
    // the device card's own button list, not here.
    await captureWidget(tester, name: 'sram_panel_disabled', width: 380, locales: locales, builder: panel);
  });

  // ── Guided sheet stages (real widget via debugGuidedSheetBody) ────────────
  testWidgets('sheet — setup confirm', (tester) async {
    await captureWidget(tester, name: 'sram_sheet_setup_confirm', width: 440, locales: locales,
        builder: (c) => setupBody(c, SramAxs.debugStageConfirm));
  });

  // running: item 0 done, item 1 spinning → infinite spinner, so settle:false.
  testWidgets('sheet — running', (tester) async {
    await captureWidget(tester, name: 'sram_sheet_running', width: 440, locales: locales, settle: false,
        builder: (c) => setupBody(c, SramAxs.debugStageRunning, runningStep: 1));
  });

  // authorize: pulsing AXS rings + blinking LED are infinite, so settle:false.
  testWidgets('sheet — authorize', (tester) async {
    await captureWidget(tester, name: 'sram_sheet_authorize', width: 440, locales: locales, settle: false,
        builder: (c) => setupBody(c, SramAxs.debugStageAuthorize));
  });

  testWidgets('sheet — setup success', (tester) async {
    await captureWidget(tester, name: 'sram_sheet_setup_success', width: 440, locales: locales,
        builder: (c) => setupBody(c, SramAxs.debugStageSuccess));
  });

  testWidgets('sheet — error', (tester) async {
    await captureWidget(tester, name: 'sram_sheet_error', width: 440, locales: locales,
        builder: (c) => setupBody(c, SramAxs.debugStageError));
  });

  testWidgets('sheet — restore confirm', (tester) async {
    await captureWidget(tester, name: 'sram_sheet_restore_confirm', width: 440, locales: locales,
        builder: (c) => restoreBody(c, SramAxs.debugStageConfirm));
  });

  testWidgets('sheet — restore success', (tester) async {
    await captureWidget(tester, name: 'sram_sheet_restore_success', width: 440, locales: locales,
        builder: (c) => restoreBody(c, SramAxs.debugStageSuccess));
  });

  // ── Discovered button names (§6.4) ───────────────────────────────────────
  testWidgets('discovered controls (button names)', (tester) async {
    const left = SramDeviceInfo(serial: 100, model: 1007, deviceType: 0);
    const right = SramDeviceInfo(serial: 200, model: 1007, deviceType: 1);
    // (info, serial, mask) → §6.4 name, exactly as the keymap shows them.
    final names = <(String, String)>[
      (device.buttonNameFor(left, 100, 1), 'Left paddle'),
      (device.buttonNameFor(left, 100, 2), 'Left auxiliary button'),
      (device.buttonNameFor(right, 200, 1), 'Right paddle'),
      (device.buttonNameFor(right, 200, 2), 'Right auxiliary button'),
    ];
    await captureWidget(tester, name: 'sram_button_names', width: 380, locales: const ['en'],
        builder: (c) => Card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final (name, hint) in names)
                    Basic(
                      leading: const Icon(LucideIcons.gamepad),
                      title: Text(name),
                      subtitle: Text(hint).muted().small,
                    ).withPadding(vertical: 6),
                ],
              ),
            ));
  });
}
