//INFO: This is a stub - contact me if you need the full implementation.
//
// FAKE placeholder UUIDs / values; the D-Fly indication encoding is stubbed.

import 'dart:typed_data';

import 'package:prop/emulators/ble_definition.dart';
import 'package:prop/emulators/definitions/proxy_bike_definition.dart';
import 'package:universal_ble/universal_ble.dart';

/// State of a single D-Fly channel. FAKE placeholder values.
enum Di2ButtonState {
  released(0x00),
  shortPress(0x01),
  longPress(0x02),
  doublePress(0x03)
  ;

  final int value;
  const Di2ButtonState(this.value);
}

/// Proxy definition for a Shimano Di2 wireless shifter (D-Fly).
class Di2Definition extends ProxyBikeDefinition {
  static const String SERVICE_UUID = '00000000-0000-0000-0000-0000000000d0';
  static const String SERVICE_UUID_ALTERNATIVE = '00000000-0000-0000-0000-0000000000d1';
  static const String D_FLY_CHANNEL_UUID = '00000000-0000-0000-0000-0000000000d2';

  final bool standalone;

  Di2Definition({
    required super.services,
    required super.device,
    required super.data,
    this.standalone = false,
  });

  /// Virtual Di2 peripheral with no upstream device.
  Di2Definition.standalone({required super.data})
    : standalone = true,
      super(
        services: <BleService>[
          BleService(
            SERVICE_UUID,
            [
              BleCharacteristic(D_FLY_CHANNEL_UUID, [CharacteristicProperty.indicate], []),
            ],
          ),
        ],
        device: BleDevice(deviceId: 'bikecontrol-di2', name: 'BikeControl Di2'),
      );

  @override
  PeripheralAdvertisement? get advertisement => PeripheralAdvertisement(
    name: device.name,
    manufacturerData: ManufacturerData(0x0000, Uint8List(0)),
    serviceUUIDs: [SERVICE_UUID],
  );

  @override
  void onWriteRequest(String characteristicUUID, List<int> characteristicData) {
    if (standalone) return;
    super.onWriteRequest(characteristicUUID, characteristicData);
  }

  @override
  Future<Uint8List>? onReadRequest(String characteristicUUID) {
    if (standalone) return null;
    return super.onReadRequest(characteristicUUID);
  }

  @override
  void onEnableNotificationRequest(String characteristicUUID) {
    if (standalone) return;
    super.onEnableNotificationRequest(characteristicUUID);
  }

  /// Stubbed: the full implementation encodes a D-Fly channel indication.
  void sendChannelStates(List<Di2ButtonState> states) {}

  /// Stubbed: the full implementation emits a single channel transition.
  void sendChannelState(
    int channelIndex,
    Di2ButtonState state, {
    int totalChannels = 4,
  }) {}
}
