/// One-tap fix dispatcher for the network self-test rows (Task 11) and the
/// troubleshooting page (Task 12).
///
/// Unlike the rest of `network_self_test/` this file is deliberately not a
/// pure data/model layer: it is the action layer, so it imports `core`,
/// Flutter widgets, and plugin APIs directly.
library;

import 'package:bike_control/bluetooth/devices/openbikecontrol/obp_mdns_backend.dart';
import 'package:bike_control/gen/l10n.dart';
import 'package:bike_control/main.dart' show recordError;
import 'package:bike_control/services/local_network_access.dart';
import 'package:bike_control/utils/core.dart';
import 'package:bike_control/widgets/ui/connection_method.dart';
import 'package:bike_control/widgets/ui/toast.dart';
import 'package:flutter/foundation.dart';
import 'package:local_network_permission/local_network_permission.dart';
import 'package:prop/prop.dart' show LogLevel;
import 'package:shadcn_flutter/shadcn_flutter.dart' show BuildContext;
import 'package:url_launcher/url_launcher_string.dart';

import 'network_check.dart';

/// Executes one fix. Returns true when the action completed (not necessarily
/// that it helped). Failures toast + recordError and return false.
Future<bool> runNetworkFix(BuildContext context, NetworkFixId fix) async {
  switch (fix) {
    case NetworkFixId.restartMethod:
      // The caller (the troubleshooting page) disables this button while
      // connected, so reaching here with a live connection is defensive —
      // refuse silently rather than restarting a connection that works.
      if (core.obpMdnsEmulator.isConnected.value) {
        return false;
      }
      try {
        await core.obpMdnsEmulator.stopServer();
        await core.obpMdnsEmulator.startServer();
        return true;
      } catch (e, s) {
        recordError(e, s, context: 'runNetworkFix.restartMethod');
        buildToast(
          level: LogLevel.LOGLEVEL_ERROR,
          title: AppLocalizations.current.errorStartingOpenBikeControlServer,
        );
        return false;
      }

    case NetworkFixId.useOsResponderForObc:
      return switchObpBackend(ObpMdnsBackend.osResponder);

    case NetworkFixId.useResponderForObc:
      return switchObpBackend(ObpMdnsBackend.platformDefault);

    case NetworkFixId.switchToLocal:
      try {
        return await enableLocalControl(context);
      } catch (e, s) {
        recordError(e, s, context: 'runNetworkFix.switchToLocal');
        return false;
      }

    case NetworkFixId.openFirewallSettings:
      try {
        return await launchUrlString('ms-settings:windowsdefender', mode: LaunchMode.externalApplication);
      } catch (e, s) {
        recordError(e, s, context: 'runNetworkFix.openFirewallSettings');
        return false;
      }

    case NetworkFixId.openBonjourDownload:
      try {
        return await launchUrlString(
          'https://octoclip.app/learn/how-to-install-bonjour-on-windows/',
          mode: LaunchMode.externalApplication,
        );
      } catch (e, s) {
        recordError(e, s, context: 'runNetworkFix.openBonjourDownload');
        return false;
      }

    case NetworkFixId.openLocalNetworkSettings:
      try {
        await LocalNetworkPermission.openSettings();
        LocalNetworkAccess.invalidate();
        return true;
      } catch (e, s) {
        recordError(e, s, context: 'runNetworkFix.openLocalNetworkSettings');
        return false;
      }

    case NetworkFixId.sendToSupport:
      // Owned by the page (it needs to push SupportChatPage) — a caller
      // that dispatches this here instead of routing it itself is a wiring
      // bug, so this only returns false and never runs in release builds.
      assert(false, 'sendToSupport must be handled by the page, not runNetworkFix');
      return false;
  }
}

/// Testable core of the backend switch (no BuildContext): set pref →
/// stopServer → startServer; on start failure: recordError, restore the
/// previous pref, restart on it (best effort), rethrow-free return false.
@visibleForTesting
Future<bool> switchObpBackend(ObpMdnsBackend target) async {
  final previous = core.settings.getObpMdnsBackend();
  await core.settings.setObpMdnsBackend(target);
  await core.obpMdnsEmulator.stopServer();
  try {
    await core.obpMdnsEmulator.startServer();
    return true;
  } catch (e, s) {
    recordError(e, s, context: 'switchObpBackend');
    await core.settings.setObpMdnsBackend(previous);
    try {
      await core.obpMdnsEmulator.startServer();
    } catch (e2, s2) {
      recordError(e2, s2, context: 'switchObpBackend');
    }
    return false;
  }
}
