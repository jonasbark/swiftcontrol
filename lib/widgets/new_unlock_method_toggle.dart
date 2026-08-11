import 'package:bike_control/bluetooth/devices/zwift/zwift_clickv2.dart';
import 'package:bike_control/bluetooth/devices/zwift/zwift_clickv2_right_side.dart';
import 'package:bike_control/utils/click_v2_onboarding.dart';
import 'package:bike_control/utils/core.dart';
import 'package:bike_control/utils/i18n_extension.dart';
import 'package:bike_control/widgets/ui/toast.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

/// Toggle that switches between the new split left/right Click V2 controllers
/// (with the unlock handling the right side avoids entirely) and the legacy
/// single [ZwiftClickV2]. Shown in the settings of all three Click V2 device
/// variants. Defaults on.
///
/// Flipping it re-creates the connected Click(s): a plain disconnect drops them
/// from the scan cache so the active scan rediscovers and reconnects them with
/// the representation the new setting now selects.
class NewUnlockMethodToggle extends StatefulWidget {
  const NewUnlockMethodToggle({super.key});

  @override
  State<NewUnlockMethodToggle> createState() => _NewUnlockMethodToggleState();
}

class _NewUnlockMethodToggleState extends State<NewUnlockMethodToggle> {
  late bool _enabled = core.settings.getUseNewUnlockMethod();

  Future<void> _onChanged(bool value) async {
    // Read localised text up front: disconnecting below removes this card from
    // the tree, so `context` may be unmounted by the time we show the toast.
    final reconnectingMessage = context.i18n.unlock_newMethodReconnecting;

    setState(() => _enabled = value);
    await core.settings.setUseNewUnlockMethod(value);

    if (!value) {
      // Right-side-only cannot survive this switch. In the legacy
      // representation the LEFT puck is what becomes the unified
      // [ZwiftClickV2] and the right puck builds nothing at all (see
      // BluetoothDevice.fromScanResult) — so leaving the left side on the
      // ignored list here leaves the rider with no Click whatsoever, and the
      // chain falls back to its empty "Controller" placeholder.
      await core.settings.setClickV2RightSideOnly(false);
      await ClickV2Onboarding.restoreLeftSides();
    } else if (!core.settings.getUnlockWithZwift()) {
      // Switching the split representation ON is the rider asking for the
      // handling whose whole point is the right puck needing no unlock — so
      // land them on it, rather than on the left puck's restart loop, which is
      // what the legacy mode they just left already was. A rider who
      // deliberately chose unlock-with-Zwift keeps both sides; this only
      // covers the default.
      //
      // Before the disconnect below, while the left puck is still a live
      // device: that is what puts it on the ignored list, and it is the same
      // physical device whether it currently exists as the unified controller
      // or as a split left side.
      await ClickV2Onboarding.chooseRightSideOnly();
    }

    final clicks = core.connection.bluetoothDevices
        .where((d) => d is ZwiftClickV2 || d is ZwiftClickV2RightSide)
        .toList();
    for (final device in clicks) {
      await core.connection.disconnect(device, forget: false, persistForget: false);
    }
    // A full restart, not just the disconnects above. The scanner dedupes
    // against its cached adverts, and in the legacy representation the right
    // puck's advert was cached while resolving to no device at all
    // (fromScanResult returns null for it) — so without clearing that cache the
    // right side is never rebuilt, and the rider ends up with the one puck this
    // switch was meant to move them off.
    await core.connection.stop();
    await core.connection.performScanning();
    if (clicks.isNotEmpty) {
      buildToast(title: reconnectingMessage);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 4,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(child: Text(context.i18n.unlock_newMethod).small.semiBold),
            Switch(value: _enabled, onChanged: _onChanged),
          ],
        ),
        Text(context.i18n.unlock_newMethodDescription).xSmall.muted,
      ],
    );
  }
}
