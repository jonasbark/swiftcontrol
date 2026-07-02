import 'dart:typed_data';

import 'package:universal_ble/universal_ble.dart';

import '../emulated_ble_platform.dart';
import '../emulated_peripherals.dart';
import '../emulation_manager.dart';
import '../emulation_profile.dart';

/// All three Elite devices share the same base service UUID.
const _eliteServiceUuid = '347b0001-7635-408b-8918-8ff3949ce592';

// Sterzo (also the Rizer steering characteristic).
const _steeringMeasurementUuid = '347b0030-7635-408b-8918-8ff3949ce592';
const _sterzoControlUuid = '347b0031-7635-408b-8918-8ff3949ce592';
const _sterzoChallengeUuid = '347b0032-7635-408b-8918-8ff3949ce592';

// Square.
const _squareCharacteristicUuid = '347b0043-7635-408b-8918-8ff3949ce592';

// Rizer.
const _rizerWriteUuid = '347b0020-7635-408b-8918-8ff3949ce592';
const _rizerStatusUuid = '347b0021-7635-408b-8918-8ff3949ce592';
const _rizerInclineUuid = '347b0022-7635-408b-8918-8ff3949ce592';

/// Steering angle as the devices send it: float32 little-endian degrees.
List<int> steeringAngleBytes(double degrees) {
  final data = ByteData(4)..setFloat32(0, degrees, Endian.little);
  return data.buffer.asUint8List().toList();
}

/// Shared steering controls. The app averages the first 10 samples into a
/// zero offset, so Calibrate must run once before the steer actions.
List<EmulatedInput> steeringInputs(EmulationSession session, String measurementCharacteristicUuid) {
  void angle(double degrees) => session.notify(measurementCharacteristicUuid, steeringAngleBytes(degrees));
  return [
    EmulatedAction('Calibrate (center)', run: () {
      for (var i = 0; i < 10; i++) {
        angle(0);
      }
    }),
    EmulatedAction('Steer left (−15°)', run: () => angle(-15)),
    EmulatedAction('Center (0°)', run: () => angle(0)),
    EmulatedAction('Steer right (+15°)', run: () => angle(15)),
    EmulatedAction('Hard right (+45°)', run: () => angle(45)),
  ];
}

FakePeripheral buildEliteSterzo({String deviceId = 'emulated:sterzo'}) {
  final peripheral = FakePeripheral(
    deviceId: deviceId,
    name: 'STERZO 1337',
    advertisedServices: const [_eliteServiceUuid],
  );
  peripheral.services.addAll([
    BleService(_eliteServiceUuid, [
      bleChar(_steeringMeasurementUuid, [CharacteristicProperty.notify]),
      bleChar(_sterzoControlUuid, [CharacteristicProperty.write]),
      bleChar(_sterzoChallengeUuid, [CharacteristicProperty.indicate]),
    ]),
    ...deviceInfoServices(peripheral),
  ]);
  return peripheral;
}

/// When the app requests the challenge ([0x03, 0x10] on the control point),
/// indicate challenge 0x002A. The app's answer ([0x03, 0x11, c0, c1]) and the
/// activation ([0x02, 0x02]) are accepted without validation.
void autoRespondToSterzoChallenge(FakeUniversalBlePlatform ble, FakePeripheral peripheral) {
  peripheral.onWrite = (service, characteristic, value) {
    final isControl = characteristic.toLowerCase() == _sterzoControlUuid;
    if (isControl && value.length >= 2 && value[0] == 0x03 && value[1] == 0x10) {
      ble.notify(peripheral.deviceId, _sterzoChallengeUuid, const [0x03, 0x10, 0x00, 0x2a]);
    }
  };
}

final eliteSterzoProfile = EmulationProfile(
  name: 'Elite Sterzo',
  category: EmulationCategory.steering,
  build: buildEliteSterzo,
  onRegistered: autoRespondToSterzoChallenge,
  inputs: (session) => steeringInputs(session, _steeringMeasurementUuid),
);

/// 12-byte Square frame; the 4-byte button code sits at bytes 3-6.
List<int> squareNotification(String code8Hex) {
  assert(code8Hex.length == 8);
  final code = [
    for (var i = 0; i < 8; i += 2) int.parse(code8Hex.substring(i, i + 2), radix: 16),
  ];
  return [0x03, 0x01, 0x53, ...code, 0x03, 0x18, 0xf4, 0x01, 0x01];
}

/// Button code table from EliteSquare.BUTTON_MAPPING (elite_square.dart:84-105).
const _squareButtonCodes = <String, String>{
  'Up': '00000200',
  'Left': '00000100',
  'Down': '00000800',
  'Right': '00000400',
  'X': '00002000',
  'Square': '00001000',
  'Campagnolo left': '00008000',
  'Left brake': '00004000',
  'Left shift 1': '00000002',
  'Left shift 2': '00000001',
  'Y': '02000000',
  'A': '01000000',
  'B': '08000000',
  'Z': '04000000',
  'Circle': '20000000',
  'Triangle': '10000000',
  'Campagnolo right': '80000000',
  'Right brake': '40000000',
  'Right shift 1': '00020000',
  'Right shift 2': '00010000',
};

FakePeripheral buildEliteSquare({String deviceId = 'emulated:square'}) {
  final peripheral = FakePeripheral(
    deviceId: deviceId,
    name: 'SQUARE',
    advertisedServices: const [_eliteServiceUuid],
  );
  peripheral.services.addAll([
    BleService(_eliteServiceUuid, [
      bleChar(_squareCharacteristicUuid, [CharacteristicProperty.notify]),
    ]),
    ...deviceInfoServices(peripheral),
  ]);
  return peripheral;
}

final eliteSquareProfile = EmulationProfile(
  name: 'Elite Square',
  category: EmulationCategory.controller,
  build: buildEliteSquare,
  inputs: (session) => [
    for (final entry in _squareButtonCodes.entries)
      EmulatedButton(
        entry.key,
        // EliteSquare only fires a click on a *change* from the previous
        // notification and treats its very first-ever notification as the
        // baseline (no click). Lead with the idle frame so the pressed frame
        // right after it always reads as a transition — a no-op once a prior
        // release already left the device at idle.
        onDown: () {
          session.notify(_squareCharacteristicUuid, squareNotification('00000000'));
          session.notify(_squareCharacteristicUuid, squareNotification(entry.value));
        },
        onUp: () => session.notify(_squareCharacteristicUuid, squareNotification('00000000')),
      ),
  ],
);

FakePeripheral buildEliteRizer({String deviceId = 'emulated:rizer'}) {
  final peripheral = FakePeripheral(
    deviceId: deviceId,
    name: 'RIZER 1337',
    advertisedServices: const [_eliteServiceUuid],
  );
  peripheral.services.addAll([
    BleService(_eliteServiceUuid, [
      bleChar(_rizerWriteUuid, [CharacteristicProperty.write]),
      bleChar(_rizerStatusUuid, [CharacteristicProperty.notify]),
      bleChar(_rizerInclineUuid, [CharacteristicProperty.notify]),
      bleChar(_steeringMeasurementUuid, [CharacteristicProperty.notify]),
    ]),
    ...deviceInfoServices(peripheral),
  ]);
  return peripheral;
}

final eliteRizerProfile = EmulationProfile(
  name: 'Elite Rizer',
  category: EmulationCategory.steering,
  build: buildEliteRizer,
  inputs: (session) => steeringInputs(session, _steeringMeasurementUuid),
  decodeWrite: (characteristicUuid, value) {
    if (characteristicUuid != _rizerWriteUuid || value.length != 3 || value[0] != 0x0a) return null;
    var tenths = value[1] | (value[2] << 8);
    if (tenths >= 0x8000) tenths -= 0x10000;
    return 'Set incline ${(tenths / 10).toStringAsFixed(1)}%';
  },
);
