import 'package:bike_control/bluetooth/devices/base_device.dart';
import 'package:bike_control/bluetooth/devices/zwift/zwift_clickv2.dart';
import 'package:bike_control/bluetooth/devices/zwift/zwift_clickv2_left_side.dart';
import 'package:bike_control/bluetooth/devices/zwift/zwift_clickv2_right_side.dart';
import 'package:bike_control/bluetooth/messages/notification.dart';
import 'package:bike_control/gen/l10n.dart';
import 'package:bike_control/main.dart';
import 'package:bike_control/utils/core.dart';
import 'package:prop/devices/click_logic.dart';
import 'package:prop/prop.dart' show LogLevel;

/// Policy for the one-time Zwift Click V2 unlock-mode onboarding.
///
/// Zwift locks the Click V2 to their own app. BikeControl implements two
/// workarounds, and which one suits a rider is a real trade-off — so a newly
/// discovered Click V2 is held out of the connect queue until the rider has
/// seen the explainer and picked one.
///
/// Every consumer (the device classes' connect gate, the placeholder card and
/// the onboarding page) reads this class rather than assembling its own
/// settings checks, so the rule lives in exactly one place.
abstract final class ClickV2Onboarding {
  /// Whether a discovered Click V2 should be held back for onboarding.
  static bool get isPending {
    // Screenshot frames connect fake controllers directly and must never be
    // interrupted by an onboarding card.
    if (screenshotMode) return false;
    if (!core.settings.isInitialized) return false;
    if (core.settings.getClickV2OnboardingDone()) return false;
    // `unlock_mode` defaults to false, so a true value can only come from a
    // deliberate past choice. Those riders are already settled — don't
    // re-onboard them.
    if (core.settings.getUnlockWithZwift()) return false;
    return true;
  }

  /// Every discovered Click V2 side that is currently disconnected — both
  /// split sides and the legacy unified representation.
  ///
  /// NOT gated on [isPending]. That would seem right for a getter named
  /// "pendingDevices", but [chooseRightSideOnly]/[chooseUnlockWithZwift] write
  /// the setting that flips [isPending] to false *before* they call
  /// [_connectPending] — by the time [_connectPending] needs this list,
  /// `isPending` is already false. So this getter stays ungated and instead
  /// means "every disconnected Click V2 side, pending or not"; callers that
  /// need "still awaiting onboarding" must additionally check [isPending]
  /// themselves (see `_hasPendingClickV2` in DevicePage). [_connectPending]
  /// compensates for the over-broad result by skipping devices the battery
  /// saver deliberately suppressed (see [Connection.isAutoReconnectSuppressed]).
  static List<BaseDevice> get pendingDevices => core.connection.devices
      .where((d) => d is ZwiftClickV2 || d is ZwiftClickV2RightSide)
      .where((d) => !d.isConnected)
      .toList();

  /// Right-side-only: the puck Zwift never locked, on its own. It needs no
  /// unlock, ever, and no restarts — the price is that the left puck's D-pad
  /// (steering, action bar) is not available.
  ///
  /// The left side is held back rather than ignored, so this stays reversible
  /// from the explainer's "Set up again" without a trip through the ignored
  /// devices list.
  static Future<void> chooseRightSideOnly() async {
    await core.settings.setUnlockWithZwift(false);
    await core.settings.setClickV2RightSideOnly(true);
    // With one puck doing the work, the default keymap would leave the rider
    // able to shift in one direction only: Zwift's built-in map binds the
    // right paddle to shiftUp and the *left* paddle to shiftDown. This is the
    // same remap the right card's "Use the right side only" action applies.
    //
    // Isolated: the remap is a convenience on top of the mode, and needs a
    // trainer app to have been picked. If it can't run — no app selected yet,
    // a keymap that won't persist — the rider's actual choice must still be
    // recorded and applied below, not abandoned half-written.
    try {
      ZwiftClickV2RightSide.configureRightSideShiftingKeymap();
    } catch (e, stack) {
      recordError(e, stack, context: 'ClickV2Onboarding.configureRightSideShiftingKeymap');
    }
    // The right side only exists as its own device in the split
    // representation. If the rider had that switched off, turn it back on and
    // drop the stale device objects so the active scan rebuilds them as split
    // left/right instances. They are not connected yet, so this costs nothing.
    if (!core.settings.getUseNewUnlockMethod()) {
      await core.settings.setUseNewUnlockMethod(true);
      for (final device in pendingDevices) {
        // forget: false is what drops the cached scan result, so the active
        // scan rediscovers the controller and rebuilds it with the class the
        // new setting selects. This mirrors NewUnlockMethodToggle exactly.
        // persistForget: false keeps it out of the ignored-devices list.
        await core.connection.disconnect(device, forget: false, persistForget: false);
      }
      await _complete();
      await core.connection.performScanning();
      return;
    }
    // "Set up again" can reach this method while a left side is ALREADY
    // connected. Its restart loop has to stop now, not whenever the firmware
    // next drops the link: the left side is no longer part of this setup, and
    // ClickLogic's timer is shared with the right side's handshake.
    ClickLogic.resetTimer();
    // Materialised: disconnect() mutates core.connection.devices, and a lazy
    // whereType view over it throws a concurrent-modification error mid-loop.
    final connectedLeftSides = core.connection.devices.whereType<ZwiftClickV2LeftSide>().toList();
    for (final device in connectedLeftSides) {
      if (!device.isConnected) continue;
      try {
        await core.connection.disconnect(device, forget: false, persistForget: false);
      } catch (e, stack) {
        recordError(e, stack, context: 'ClickV2Onboarding.chooseRightSideOnly');
      }
    }
    await _complete();
    await _connectPending();
  }

  /// Unlock with Zwift: both controllers work, at the cost of re-unlocking
  /// through the Zwift app every 24 hours.
  static Future<void> chooseUnlockWithZwift() async {
    await core.settings.setUnlockWithZwift(true);
    await core.settings.setClickV2RightSideOnly(false);
    // Mirrors UnlockToggle's own Select.onChanged: switching to Zwift mode
    // must cancel any live ClickLogic reset timer immediately, or the rider
    // gets one spurious restart right after choosing the mode whose whole
    // selling point is "no restarts during your ride".
    try {
      ClickLogic.resetTimer();
    } catch (e, stack) {
      recordError(e, stack, context: 'ClickV2Onboarding.chooseUnlockWithZwift');
    }
    await _complete();
    await _connectPending();
  }

  static Future<void> _complete() async {
    await core.settings.setClickV2OnboardingDone(true);
  }

  static Future<void> _connectPending() async {
    for (final device in pendingDevices) {
      // pendingDevices is not gated on isPending (see its doc comment) and
      // returns every disconnected Click V2 side, including one the battery
      // saver deliberately put to sleep. Connecting it here would undo that
      // the moment the rider finishes an unrelated onboarding choice.
      if (core.connection.isAutoReconnectSuppressed(device)) continue;
      try {
        await core.connection.connectDevice(device);
      } catch (e, stack) {
        recordError(e, stack, context: 'ClickV2Onboarding.connectPending');
        core.connection.signalNotification(
          AlertNotification(LogLevel.LOGLEVEL_ERROR, AppLocalizations.current.clickV2Onboarding_connectFailed),
        );
      }
    }
  }
}
