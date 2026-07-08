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
/// Run: `flutter test test/sram_states_snapshot_test.dart`
/// (run on its own — do not co-run with integration tests: app_links poison.)
Future<void> main() async {
  await ensureSnapshotHarness();

  const locales = ['en', 'de'];
  const key = 'sram-snap';
  final device = SramAxs(BleDevice(deviceId: key, name: 'SRAM Rival AXS'));

  // A dialog card the way _runGuidedOperation shows it (Container + AlertDialog).
  Widget dialog(BuildContext context, {required String title, required String body, required List<Widget> actions}) {
    return Align(
      alignment: Alignment.topCenter,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 480),
        child: AlertDialog(title: Text(title), content: Text(body), actions: actions),
      ),
    );
  }

  List<Widget> cancelPrimary(BuildContext context, String primaryLabel) => [
        Button.secondary(onPressed: () {}, child: Text(context.i18n.cancel)),
        PrimaryButton(onPressed: () {}, child: Text(primaryLabel)),
      ];

  Widget panel(BuildContext context) => Card(child: Column(children: device.showAdditionalInformation(context)));

  // ── Panel states ─────────────────────────────────────────────────────────
  testWidgets('panel — not yet set up', (tester) async {
    await core.settings.setSramShiftingDisabled(key, false);
    await core.settings.clearSramBackup(key);
    await captureWidget(tester, name: 'sram_panel_setup', width: 380, locales: locales, builder: panel);
  });

  testWidgets('panel — shifting disabled', (tester) async {
    await core.settings.setSramShiftingDisabled(key, true);
    await core.settings.setSramBackup(key, {
      'd9050028-90aa-4c7c-b036-1e01fb8eb7ee': const SramReactionTrigger([0], [1]),
    });
    await captureWidget(tester, name: 'sram_panel_disabled', width: 380, locales: locales, builder: panel);
  });

  // ── Guided setup/restore dialog stages ───────────────────────────────────
  testWidgets('dialog — setup confirm', (tester) async {
    await captureWidget(tester, name: 'sram_dialog_setup_confirm', width: 440, locales: locales,
        builder: (c) => dialog(c, title: c.i18n.sramSetup, body: c.i18n.sramSetupIntro, actions: cancelPrimary(c, c.i18n.continueAction)));
  });

  testWidgets('dialog — running', (tester) async {
    await captureWidget(tester, name: 'sram_dialog_running', width: 440, locales: locales,
        builder: (c) => dialog(c, title: c.i18n.sramSetup, body: c.i18n.sramDialogRunning, actions: const []));
  });

  testWidgets('dialog — authorize (bond needed)', (tester) async {
    await captureWidget(tester, name: 'sram_dialog_authorize', width: 440, locales: locales,
        builder: (c) => dialog(c, title: c.i18n.sramAuthorizeTitle, body: c.i18n.sramAuthorizeBody, actions: cancelPrimary(c, c.i18n.retry)));
  });

  testWidgets('dialog — setup success', (tester) async {
    await captureWidget(tester, name: 'sram_dialog_setup_success', width: 440, locales: locales,
        builder: (c) => dialog(c, title: c.i18n.done, body: c.i18n.sramSetupSuccess,
            actions: [PrimaryButton(onPressed: () {}, child: Text(c.i18n.done))]));
  });

  testWidgets('dialog — error', (tester) async {
    await captureWidget(tester, name: 'sram_dialog_error', width: 440, locales: locales,
        builder: (c) => dialog(c, title: c.i18n.sramErrorTitle, body: c.i18n.sramGenericError, actions: cancelPrimary(c, c.i18n.retry)));
  });

  testWidgets('dialog — restore confirm', (tester) async {
    await captureWidget(tester, name: 'sram_dialog_restore_confirm', width: 440, locales: locales,
        builder: (c) => dialog(c, title: c.i18n.sramRestore, body: c.i18n.sramRestoreIntro, actions: cancelPrimary(c, c.i18n.continueAction)));
  });

  testWidgets('dialog — restore success', (tester) async {
    await captureWidget(tester, name: 'sram_dialog_restore_success', width: 440, locales: locales,
        builder: (c) => dialog(c, title: c.i18n.done, body: c.i18n.sramRestoreSuccess,
            actions: [PrimaryButton(onPressed: () {}, child: Text(c.i18n.done))]));
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
