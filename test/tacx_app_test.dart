import 'package:bike_control/bluetooth/devices/elite/elite_square.dart';
import 'package:bike_control/bluetooth/devices/zwift/constants.dart';
import 'package:bike_control/utils/keymap/apps/supported_app.dart';
import 'package:bike_control/utils/keymap/apps/tacx.dart';
import 'package:bike_control/utils/keymap/buttons.dart';
import 'package:bike_control/utils/keymap/keymap.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Tacx tacx() => SupportedApp.supportedApps.whereType<Tacx>().single;

  KeyPair pairFor(ControllerButton button) =>
      tacx().keymap.keyPairs.firstWhere((p) => p.buttons.contains(button));

  test('Tacx Training is registered exactly once, as a third-party app', () {
    final matches = SupportedApp.supportedApps.where((app) => app.name == 'Tacx Training');
    expect(matches, hasLength(1));
    // No partnership, so the chooser badge must not claim one.
    expect(matches.single.officialIntegration, isFalse);
    expect(matches.single.officialUrl, startsWith('https://'));
  });

  test('Tacx exposes no controller transport', () {
    // Tacx pairs no external controllers, so every direct method must report
    // unsupported — buttons only reach it as simulated keystrokes, and gears
    // come from the Bridge.
    expect(tacx().connections, isEmpty);
    for (final method in AppConnectionMethod.values) {
      expect(tacx().supportLevel(method), isNull, reason: '$method must not be advertised');
    }
  });

  group('keymap mirrors Tacx Settings → Keyboard Shortcuts', () {
    test('Space pauses/resumes, Esc quits, L skips the current step', () {
      expect(pairFor(ZwiftButtons.z).logicalKey, LogicalKeyboardKey.space);
      expect(pairFor(ZwiftButtons.z).inGameAction, InGameAction.pause);

      expect(pairFor(ZwiftButtons.b).logicalKey, LogicalKeyboardKey.escape);
      expect(pairFor(ZwiftButtons.b).inGameAction, InGameAction.back);

      expect(pairFor(ZwiftButtons.y).logicalKey, LogicalKeyboardKey.keyL);
      expect(pairFor(ZwiftButtons.y).inGameAction, InGameAction.skipInterval);
    });

    test('the Elite Square face buttons ride along on the same pairs', () {
      expect(pairFor(EliteSquareButtons.z).logicalKey, LogicalKeyboardKey.space);
      expect(pairFor(EliteSquareButtons.b).logicalKey, LogicalKeyboardKey.escape);
      expect(pairFor(EliteSquareButtons.y).logicalKey, LogicalKeyboardKey.keyL);
    });

    test('Tab changes training views', () {
      expect(pairFor(ZwiftButtons.onOffLeft).logicalKey, LogicalKeyboardKey.tab);
      expect(pairFor(ZwiftButtons.onOffLeft).inGameAction, InGameAction.toggleUi);
    });

    test('the D-pad drives difficulty and screen paging', () {
      expect(pairFor(ZwiftButtons.navigationUp).logicalKey, LogicalKeyboardKey.arrowUp);
      expect(pairFor(ZwiftButtons.navigationUp).inGameAction, InGameAction.increaseResistance);

      expect(pairFor(ZwiftButtons.navigationDown).logicalKey, LogicalKeyboardKey.arrowDown);
      expect(pairFor(ZwiftButtons.navigationDown).inGameAction, InGameAction.decreaseResistance);

      expect(pairFor(ZwiftButtons.navigationLeft).logicalKey, LogicalKeyboardKey.arrowLeft);
      expect(pairFor(ZwiftButtons.navigationLeft).inGameAction, InGameAction.navigateLeft);

      expect(pairFor(ZwiftButtons.navigationRight).logicalKey, LogicalKeyboardKey.arrowRight);
      expect(pairFor(ZwiftButtons.navigationRight).inGameAction, InGameAction.navigateRight);
    });

    test('no entry uses a key Tacx cannot receive', () {
      // Tacx's entire shortcut vocabulary — anything else is a keystroke the
      // app has no binding for, i.e. a button that silently does nothing.
      final vocabulary = {
        LogicalKeyboardKey.enter,
        LogicalKeyboardKey.escape,
        LogicalKeyboardKey.tab,
        LogicalKeyboardKey.space,
        LogicalKeyboardKey.arrowUp,
        LogicalKeyboardKey.arrowDown,
        LogicalKeyboardKey.arrowLeft,
        LogicalKeyboardKey.arrowRight,
        LogicalKeyboardKey.keyL,
      };
      for (final pair in tacx().keymap.keyPairs) {
        final key = pair.logicalKey;
        if (key == null) continue;
        expect(vocabulary, contains(key), reason: '${pair.buttons} maps to an unsupported key');
      }
    });

    test('every entry carries an in-game action', () {
      // A key-only pair shadows the action the button would otherwise inherit
      // from ControllerButton.action via Keymap.addNewButtons, which would cost
      // the button its meaning on the Bridge.
      for (final pair in tacx().keymap.keyPairs) {
        expect(pair.inGameAction, isNotNull, reason: '${pair.buttons} has no in-game action');
      }
    });

    test('shifting is left to the Bridge', () {
      // Tacx has no shift shortcut at all; the Bridge does the virtual
      // shifting itself, so shift buttons must keep their inherited action
      // rather than be bound to a keystroke that goes nowhere.
      final shifts = tacx().keymap.keyPairs.where(
        (p) => p.inGameAction == InGameAction.shiftUp || p.inGameAction == InGameAction.shiftDown,
      );
      expect(shifts, isEmpty);
    });
  });

  test('Tacx asks the Bridge to advertise a product-id', () {
    // Tacx lists a network trainer only once it recognises this field.
    expect(tacx().trainerMdnsTxt, {'product-id': Tacx.mdnsProductId});
    expect(Tacx.mdnsProductId, isNotEmpty);
  });

  test('the product-id is the one both platforms accept', () {
    // Pinned to the value, not just "non-empty": it was found by measurement,
    // and the platforms disagree. macOS accepts any of {4614, 4354, 4753,
    // 4924}; Windows (4.85.2.0) accepts only 4354 — phantom services identical
    // but for this field were listed for 4354 and ignored for the other three
    // and for omitting it. Changing this silently drops Windows support.
    expect(Tacx.mdnsProductId, '4354');
  });

  test('no other app contributes trainer TXT fields', () {
    for (final app in SupportedApp.supportedApps.where((a) => a is! Tacx)) {
      expect(app.trainerMdnsTxt, isEmpty, reason: '${app.name} must not alter the Bridge advertisement');
    }
  });
}
