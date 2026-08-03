import 'package:bike_control/bluetooth/devices/zwift/zwift_clickv2_left_side.dart';
import 'package:bike_control/bluetooth/messages/notification.dart';
import 'package:bike_control/pages/click_v2_onboarding.dart';
import 'package:bike_control/utils/core.dart';
import 'package:bike_control/utils/i18n_extension.dart';
import 'package:prop/devices/click_logic.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:url_launcher/url_launcher_string.dart';

class UnlockToggle extends StatefulWidget {
  final ZwiftClickV2LeftSide device;
  final List<Widget> children;
  const UnlockToggle({super.key, required this.device, required this.children});

  @override
  State<UnlockToggle> createState() => _UnlockToggleState();
}

class _UnlockToggleState extends State<UnlockToggle> {
  bool _unlockWithZwift = false;

  @override
  void initState() {
    _unlockWithZwift = core.settings.getUnlockWithZwift();
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 8,
      children: [
        Row(
          children: [
            Text(context.i18n.unlock_mode).small.semiBold,
            IconButton.link(
              icon: Icon(Icons.help_outline),
              onPressed: () {
                launchUrlString('https://bikecontrol.app/blog/zwift-click-v2-with-other-trainer-apps');
              },
            ),
            const Spacer(),
            // The explainer that introduced these two modes stays reachable
            // after onboarding, so the trade-offs can be re-read later.
            Button.ghost(
              onPressed: () => context.push(const ClickV2OnboardingPage()),
              child: Text(context.i18n.clickV2Onboarding_setUpAgain).xSmall,
            ),
          ],
        ),
        Select<bool>(
          value: _unlockWithZwift,
          popup: SelectPopup(
            items: SelectItemList(
              children: [
                SelectItemButton(
                  value: false,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(context.i18n.unlock_modeRestart).bold,
                      Text(context.i18n.unlock_modeRestartDescription).xSmall.muted,
                    ],
                  ),
                ),
                SelectItemButton(
                  value: true,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(context.i18n.unlock_modeZwift).bold,
                      Text(context.i18n.unlock_modeZwiftDescription).xSmall.muted,
                    ],
                  ),
                ),
              ],
            ),
          ).call,
          itemBuilder: (context, value) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(value ? context.i18n.unlock_modeZwift : context.i18n.unlock_modeRestart),
              Text(
                value ? context.i18n.unlock_modeZwiftDescription : context.i18n.unlock_modeRestartDescription,
              ).xSmall.normal.muted,
            ],
          ),
          onChanged: (unlockWithZwift) async {
            if (unlockWithZwift == null) return;
            setState(() {
              _unlockWithZwift = unlockWithZwift;
            });
            await core.settings.setUnlockWithZwift(unlockWithZwift);
            if (unlockWithZwift) {
              ClickLogic.resetTimer();
            } else {
              // `services` is populated by BluetoothDevice.connect() after
              // discovery completes, but `isConnected` flips true earlier --
              // from the raw BLE connection-state listener -- so there's a
              // narrow window where this fires with services still null.
              // The rider's choice still needs to be recorded either way;
              // only the handshake itself is skipped when we can't send it.
              final services = widget.device.services;
              if (services != null) {
                ClickLogic.setupHandshake(services, widget.device.device.deviceId, isRight: false);
              } else {
                core.connection.signalNotification(
                  LogNotification(
                    'UnlockToggle: skipped setupHandshake for ${widget.device.device.deviceId} -- services not ready yet',
                  ),
                );
              }
            }
          },
        ),

        if (_unlockWithZwift) ...widget.children,
      ],
    );
  }
}
