import 'package:bike_control/utils/keymap/apps/supported_app.dart';

import '../keymap.dart';

/// FulGaz (https://fulgaz.com).
///
/// The app takes no input from a controller at all. Decompiling 7.0.6
/// (Android) and 7.0.9 (macOS) found no key handling, no gamepad, no
/// OpenBikeControl and no Zwift service — so [connections] is empty and the
/// keymap stays empty too, because there is no shortcut to press.
///
/// What is left is the trainer. FulGaz finds trainers over Bluetooth only:
/// its macOS build ships a "Direct Connect Trainers" local-network permission
/// string, but nothing behind it — no Bonjour service types, no mDNS, not a
/// single UDP socket — so [virtualShiftingTransports] is Bluetooth alone.
///
/// That leaves exactly one arrangement that works: FulGaz on a second device,
/// riding the Bridge as its Bluetooth trainer while BikeControl does the
/// virtual shifting. Gears never leave BikeControl — FulGaz has no virtual
/// shifting of its own, and the gear readout it does show is telemetry it
/// reads from smart bikes.
class FulGaz extends SupportedApp {
  @override
  List<(AppConnectionMethod, ConnectionSupport)> get connections => const [];

  @override
  Set<TrainerConnectionType> get virtualShiftingTransports => const {TrainerConnectionType.bluetooth};

  @override
  bool get acceptsSimulatedInput => false;

  @override
  String? get officialUrl => 'https://fulgaz.com';

  FulGaz()
    : super(
        name: 'FulGaz',
        packageName: 'FulGaz',
        officialIntegration: false,
        keymap: Keymap(keyPairs: []),
      );
}
