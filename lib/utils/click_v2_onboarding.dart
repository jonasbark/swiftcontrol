import 'package:bike_control/bluetooth/devices/base_device.dart';
import 'package:bike_control/bluetooth/devices/zwift/zwift_clickv2.dart';
import 'package:bike_control/bluetooth/devices/zwift/zwift_clickv2_right_side.dart';
import 'package:bike_control/main.dart';
import 'package:bike_control/utils/core.dart';

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

  /// Every discovered Click V2 side currently held back by the gate. Covers
  /// both split sides and the legacy unified representation.
  static List<BaseDevice> get pendingDevices => core.connection.devices
      .where((d) => d is ZwiftClickV2 || d is ZwiftClickV2RightSide)
      .where((d) => !d.isConnected)
      .toList();

  /// Left-side-only: no Zwift unlock at all. The left controller drops out a
  /// minute after the last button press and reconnects on its own.
  static Future<void> chooseLeftSideOnly() async {
    await core.settings.setUnlockWithZwift(false);
    // This mode is driven by ClickLogic, which only runs from
    // ZwiftClickV2LeftSide — the legacy unified controller never calls it. If
    // the rider had the split representation switched off, turn it back on and
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
    await _complete();
    await _connectPending();
  }

  /// Unlock with Zwift: both controllers work, at the cost of re-unlocking
  /// through the Zwift app every 24 hours.
  static Future<void> chooseUnlockWithZwift() async {
    await core.settings.setUnlockWithZwift(true);
    await _complete();
    await _connectPending();
  }

  static Future<void> _complete() async {
    await core.settings.setClickV2OnboardingDone(true);
  }

  static Future<void> _connectPending() async {
    for (final device in pendingDevices) {
      try {
        await core.connection.connectDevice(device);
      } catch (e, stack) {
        recordError(e, stack, context: 'ClickV2Onboarding.connectPending');
      }
    }
  }
}
