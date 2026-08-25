import 'package:bike_control/bluetooth/devices/zwift/zwift_clickv2.dart';
import 'package:bike_control/gen/l10n.dart';
import 'package:bike_control/utils/core.dart';
import 'package:bike_control/utils/keymap/apps/rouvy.dart';
import 'package:bike_control/utils/keymap/apps/zwift.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_test/flutter_test.dart';
import 'package:prop/emulators/definitions/zwift_click_definition.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:universal_ble/universal_ble.dart';

ZwiftClickDefinition _clickDefinition() => ZwiftClickDefinition(
  services: const <BleService>[],
  device: BleDevice(deviceId: 'click-v2', name: 'Zwift Click'),
  data: ValueNotifier<String>(''),
  vendorMessage: null,
  isUnlocked: ValueNotifier<bool>(false),
  alreadyUnlocked: ValueNotifier<bool>(false),
  waiting: ValueNotifier<bool>(false),
  isStarted: ValueNotifier<bool>(true),
  connectionDate: DateTime(2026),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await AppLocalizations.load(const Locale('en'));
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    core.settings.prefs = await SharedPreferences.getInstance();
  });

  test('the Click definition rides on the bridge for Zwift, not for Rouvy', () {
    final click = ZwiftClickV2(BleDevice(deviceId: 'click-v2', name: 'Zwift Click'));

    core.settings.setTrainerApp(Zwift());
    expect(click.attachesClickDefToBridge, isTrue);

    core.settings.setTrainerApp(Rouvy());
    expect(click.attachesClickDefToBridge, isFalse);
  });

  test('switching apps takes the Click definition on and off the bridge composite', () {
    final click = ZwiftClickV2(BleDevice(deviceId: 'click-v2', name: 'Zwift Click'));
    final def = _clickDefinition();
    click.debugSetClickDef(def);
    addTearDown(() => ftmsEmulator.composite.detach(def));

    // Connected under Zwift: the definition sits on the shared composite.
    core.settings.setTrainerApp(Zwift());
    ftmsEmulator.composite.attach(def);

    // Zwift → Rouvy must take it off — the bridge advertises only its own
    // trainer services again.
    core.settings.setTrainerApp(Rouvy());
    click.onTrainerAppChanged();
    expect(ftmsEmulator.composite.children, isNot(contains(def)));

    // Rouvy → Zwift puts it back.
    core.settings.setTrainerApp(Zwift());
    click.onTrainerAppChanged();
    expect(ftmsEmulator.composite.children, contains(def));
  });
}
