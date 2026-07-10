import 'dart:typed_data';

import 'package:bike_control/bluetooth/devices/zwift/constants.dart';
import 'package:bike_control/bluetooth/emulation/emulated_ble_platform.dart';
import 'package:bike_control/bluetooth/emulation/emulation_manager.dart';
import 'package:bike_control/bluetooth/emulation/emulation_profile.dart';
import 'package:bike_control/bluetooth/emulation/profiles/zwift_profiles.dart';
import 'package:bike_control/gen/l10n.dart';
import 'package:bike_control/widgets/emulation_card.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:universal_ble/universal_ble.dart';

Future<void> main() async {
  await AppLocalizations.load(const Locale('en'));

  late FakeUniversalBlePlatform ble;
  late EmulationManager manager;

  setUp(() {
    ble = FakeUniversalBlePlatform();
    manager = EmulationManager()..attach(ble);
  });

  Future<void> pumpCard(WidgetTester tester, EmulationSession session) async {
    await tester.pumpWidget(
      ShadcnApp(
        localizationsDelegates: const [AppLocalizations.delegate],
        supportedLocales: const [Locale('en')],
        home: Scaffold(child: SingleChildScrollView(child: EmulationCard(session: session))),
      ),
    );
    await tester.pump();
  }

  testWidgets('renders one control per input plus the connection controls', (tester) async {
    final session = manager.start(zwiftClickProfile);
    await pumpCard(tester, session);

    expect(find.text('Shift Up (+)'), findsOneWidget);
    expect(find.text('Shift Down (−)'), findsOneWidget);
    expect(find.text('Drop connection'), findsOneWidget);
    expect(find.text('Weak signal'), findsOneWidget);
    expect(find.text('Strong signal'), findsOneWidget);
  });

  testWidgets('press and release inject pressed and released frames', (tester) async {
    final session = manager.start(zwiftClickProfile);
    final frames = <Uint8List>[];
    ble.onValueChange = (deviceId, characteristicId, value, timestamp) => frames.add(value);
    await pumpCard(tester, session);

    final gesture = await tester.startGesture(tester.getCenter(find.text('Shift Up (+)')));
    await tester.pump(const Duration(milliseconds: 50));
    await gesture.up();
    await tester.pump();

    expect(frames, hasLength(2));
    expect(frames.first.first, ZwiftConstants.CLICK_NOTIFICATION_MESSAGE_TYPE);
    expect(frames.last.first, ZwiftConstants.CLICK_NOTIFICATION_MESSAGE_TYPE);
  });

  testWidgets('write log renders decoded writes', (tester) async {
    final profile = EmulationProfile(
      name: 'Sink',
      category: EmulationCategory.accessory,
      build: () => FakePeripheral(deviceId: 'emulated:sink', name: 'Sink'),
      decodeWrite: (characteristicUuid, value) => 'Set incline 6.0%',
    );
    final session = manager.start(profile);
    await pumpCard(tester, session);

    await ble.writeValue(
      'emulated:sink',
      'service',
      'char',
      Uint8List.fromList(const [0x0a, 0x3c, 0x00]),
      BleOutputProperty.withResponse,
    );
    await tester.pump();

    expect(find.text('Set incline 6.0%'), findsOneWidget);
  });
}
