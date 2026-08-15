import 'package:bike_control/utils/core.dart';
import 'package:bike_control/utils/keymap/apps/my_whoosh.dart';
import 'package:bike_control/utils/requirements/multi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Local control is a fallback, not proof the trainer app is reachable.
///
/// It types into whatever window happens to be in front, so it reports
/// connected the moment it is switched on. With a network method also enabled
/// — the default for MyWhoosh — counting it called the app connected while the
/// connection the rider actually rides on sat unactivated, and the home chain
/// painted that link green with nothing left to do.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    core.settings.prefs = await SharedPreferences.getInstance();
    core.local.isConnected.value = false;
    core.whooshLink.isConnected.value = false;
  });

  tearDown(() {
    core.local.isConnected.value = false;
    core.whooshLink.isConnected.value = false;
  });

  /// The MyWhoosh default: its network Link enabled alongside local control.
  Future<void> enableWhooshLinkAndLocal() async {
    core.settings.setTrainerApp(MyWhoosh());
    await core.settings.setLastTarget(Target.thisDevice);
    await core.settings.setMyWhooshLinkEnabled(true);
    core.settings.setLocalEnabled(true);
  }

  test('local alone does not count while a network method is enabled', () async {
    await enableWhooshLinkAndLocal();
    core.local.isConnected.value = true;

    // The rider sees "Local" connected, but MyWhoosh is not reachable — which
    // is the whole point of the card.
    expect(core.logic.connectedTrainerConnections, isNotEmpty);
    expect(core.logic.appFacingConnections, isEmpty);
  });

  test('the network method connecting is what counts', () async {
    await enableWhooshLinkAndLocal();
    core.local.isConnected.value = true;
    core.whooshLink.isConnected.value = true;

    expect(core.logic.appFacingConnections, contains(core.whooshLink));
    // And never captions itself "Local" when the real connection is up.
    expect(core.logic.appFacingConnections.first, isNot(core.local));
  });

  test('with no network method enabled, local IS the answer', () async {
    core.settings.setLocalEnabled(true);
    core.local.isConnected.value = true;

    expect(core.logic.enabledNonLocalTrainerConnections, isEmpty);
    expect(core.logic.appFacingConnections, contains(core.local));
  });

  test('local switched on but nothing connected stays empty', () async {
    core.settings.setLocalEnabled(true);

    expect(core.logic.appFacingConnections, isEmpty);
  });
}
