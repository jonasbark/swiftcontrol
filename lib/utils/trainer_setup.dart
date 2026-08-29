import 'dart:io';

import 'package:bike_control/utils/core.dart';
import 'package:bike_control/utils/keymap/apps/bike_control.dart';
import 'package:bike_control/utils/keymap/apps/custom_app.dart';
import 'package:bike_control/utils/keymap/apps/my_whoosh.dart';
import 'package:bike_control/utils/keymap/apps/supported_app.dart';
import 'package:bike_control/utils/requirements/multi.dart';
import 'package:flutter/foundation.dart';

/// Applies the trainer app selection, stopping unsupported emulators,
/// initializing the action handler, and starting the enabled connection method.
///
/// Shared by [ConfigurationPage] and the onboarding wizard.
Future<void> applyTrainerAppSelection(SupportedApp selectedApp) async {
  if (selectedApp is! MyWhoosh) {
    if (core.whooshLink.isStarted.value) {
      core.whooshLink.stopServer();
    }
  }
  if (!selectedApp.supports(AppConnectionMethod.zwiftMdns)) {
    if (core.zwiftMdnsEmulator.isStarted.value) {
      core.zwiftMdnsEmulator.stop();
    }
    // TODO restart mDNS when advertisementName changes
  }
  if (!selectedApp.supports(AppConnectionMethod.zwiftBle)) {
    if (core.zwiftEmulator.isStarted.value) {
      core.zwiftEmulator.stopAdvertising();
    }
  }
  if (!selectedApp.supports(AppConnectionMethod.rouvyMdns)) {
    if (core.rouvyMdnsEmulator.isStarted.value) {
      core.rouvyMdnsEmulator.stop();
    }
  }
  if (core.obpMdnsEmulator.isStarted.value) {
    core.obpMdnsEmulator.stopServer();
  }
  if (core.obpBluetoothEmulator.isStarted.value) {
    core.obpBluetoothEmulator.stopServer();
  }

  core.settings.setTrainerApp(selectedApp);
  if (core.actionHandler.supportedApp == null ||
      (core.actionHandler.supportedApp is! CustomApp && selectedApp is! CustomApp)) {
    core.actionHandler.init(selectedApp);
    core.settings.setKeyMap(selectedApp);
  }
  core.logic.startEnabledConnectionMethod();

  if (selectedApp is BikeControl) {
    core.settings.setLastTarget(Target.thisDevice);
  } else if (!selectedApp.receivesButtonEvents) {
    // Nothing we can send reaches this app locally, so a stale "this device"
    // would leave the rider on a target that cannot work.
    core.settings.setLastTarget(Target.otherDevice);
  }
}

/// Applies the target selection, enabling OBP methods or local connection
/// as appropriate, and starting the enabled connection method.
///
/// Shared by [ConfigurationPage] and the onboarding wizard.
Future<void> applyTargetSelection(Target target) async {
  await core.settings.setLastTarget(target);

  if ((core.settings.getTrainerApp()?.supports(AppConnectionMethod.obpBle) == true ||
          core.settings.getTrainerApp()?.supports(AppConnectionMethod.obpMdns) == true) &&
      !core.logic.emulatorEnabled) {
    core.settings.setObpMdnsEnabled(true);
  }

  // enable local connection on Windows if the app doesn't support OBP
  if (target == Target.thisDevice &&
      !core.settings.getTrainerApp()!.supports(AppConnectionMethod.obpBle) &&
      !core.settings.getTrainerApp()!.supports(AppConnectionMethod.obpMdns) &&
      !kIsWeb &&
      Platform.isWindows) {
    core.settings.setLocalEnabled(true);
  }
  core.logic.startEnabledConnectionMethod();
}
