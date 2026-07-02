import 'package:bike_control/bluetooth/devices/zwift/constants.dart';
import 'package:bike_control/bluetooth/devices/zwift/zwift_ride.dart' show RideButtonMask;

import '../emulated_peripherals.dart';
import '../emulation_manager.dart';
import '../emulation_profile.dart';

void _clickFrame(EmulationSession session, {required bool plus, required bool minus}) {
  session.notify(
    ZwiftConstants.ZWIFT_ASYNC_CHARACTERISTIC_UUID,
    zwiftClickNotification(plusPressed: plus, minusPressed: minus),
  );
}

final zwiftClickProfile = EmulationProfile(
  name: 'Zwift Click',
  category: EmulationCategory.controller,
  build: () => buildZwiftClick(deviceId: 'emulated:zwift-click'),
  onRegistered: autoRespondToZwiftHandshake,
  inputs: (session) => [
    EmulatedButton(
      'Shift Up (+)',
      onDown: () => _clickFrame(session, plus: true, minus: false),
      onUp: () => _clickFrame(session, plus: false, minus: false),
    ),
    EmulatedButton(
      'Shift Down (−)',
      onDown: () => _clickFrame(session, plus: false, minus: true),
      onUp: () => _clickFrame(session, plus: false, minus: false),
    ),
  ],
);

/// Ride-protocol press/release inputs, one per app-side [RideButtonMask] bit.
/// Shared by every device speaking the Ride protobuf (Ride, Click V2 sides,
/// Play FW2).
List<EmulatedInput> rideMaskInputs(EmulationSession session, List<RideButtonMask> masks) {
  void send(List<RideButtonMask> pressed) {
    session.notify(ZwiftConstants.ZWIFT_ASYNC_CHARACTERISTIC_UUID, zwiftRideNotification(pressed: pressed));
  }

  return [
    for (final mask in masks)
      EmulatedButton(mask.name, onDown: () => send([mask]), onUp: () => send(const [])),
  ];
}

final zwiftRideProfile = EmulationProfile(
  name: 'Zwift Ride',
  category: EmulationCategory.controller,
  build: () => buildZwiftRide(deviceId: 'emulated:zwift-ride'),
  onRegistered: (ble, peripheral) =>
      autoRespondToZwiftHandshake(ble, peripheral, startResponse: ZwiftConstants.RESPONSE_START_PLAY),
  inputs: (session) => rideMaskInputs(session, RideButtonMask.values),
);
