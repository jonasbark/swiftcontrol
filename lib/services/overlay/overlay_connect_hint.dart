import 'dart:async';

import 'package:bike_control/bluetooth/devices/proxy/proxy_device.dart';
import 'package:bike_control/bluetooth/messages/notification.dart';
import 'package:bike_control/gen/l10n.dart';
import 'package:bike_control/main.dart' show navigatorKey, screenshotMode;
import 'package:bike_control/pages/proxy_device_details.dart';
import 'package:bike_control/utils/core.dart';
import 'package:bike_control/utils/i18n_extension.dart';
import 'package:flutter/foundation.dart';
import 'package:prop/prop.dart' show LogLevel;

/// One-time hint fired the first time a trainer app connects to the virtual
/// trainer while the gear overlay is off.
///
/// Nearly every MyWhoosh/Rouvy bridge rider pairs the virtual trainer, then
/// writes support asking why the gear shown in the trainer app doesn't sync —
/// trainer apps can't display BikeControl's virtual gears. The canonical
/// answer is the gear overlay (trainer detail page → Overlay → "Show overlay
/// during ride"), so surface exactly that, exactly once, at the moment the
/// question would otherwise arise.
class OverlayConnectHint {
  /// Fires the hint for [device] if all gates pass:
  /// - a Virtual Shifting session is active ([ProxyDevice.fitnessBike] set) —
  ///   without it there is no BikeControl-computed gear to overlay,
  /// - the overlay is not already enabled,
  /// - the hint has never fired before (persisted flag).
  ///
  /// Surfaces through the same [AlertNotification] channel as the
  /// "Connected to app" alerts: a toast plus a persistent activity-log entry,
  /// both carrying a button that deep-links to the trainer detail page's
  /// Overlay section.
  static void maybeShow(ProxyDevice device) {
    if (kIsWeb || screenshotMode) return;
    if (device.fitnessBike == null) return;
    if (core.settings.getOverlayEnabled()) return;
    if (core.settings.getOverlayConnectHintShown()) return;

    // Persist immediately so a reconnect storm can't fire the hint twice.
    unawaited(core.settings.setOverlayConnectHintShown(true));

    final l10n = AppLocalizations.current;
    final appName = core.settings.getTrainerApp()?.name ?? l10n.yourTrainerApp;
    core.connection.signalNotification(
      AlertNotification(
        LogLevel.LOGLEVEL_INFO,
        l10n.overlayConnectHint(appName),
        buttonTitle: l10n.overlayConnectHintButton,
        onTap: () {
          final context = navigatorKey.currentContext;
          if (context == null) return;
          unawaited(context.push(ProxyDeviceDetailsPage(device: device, revealOverlaySection: true)));
        },
      ),
    );
  }
}
