import 'dart:ui';

import 'package:bike_control/gen/l10n.dart';
import 'package:bike_control/main.dart';
import 'package:bike_control/utils/core.dart';
import 'package:bike_control/utils/keymap/apps/my_whoosh.dart';
import 'package:bike_control/utils/requirements/multi.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> main() async {
  await AppLocalizations.load(const Locale('en'));

  // These getters gate on desktop-local availability (showLocalControl is only
  // true on macOS/Windows/Android). This suite is meaningful on a desktop host.
  final isDesktop = !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.macOS ||
          defaultTargetPlatform == TargetPlatform.windows);

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
    screenshotMode = false;
    await core.settings.init();
    await core.settings.reset();
    core.settings.setTrainerApp(MyWhoosh());
    core.settings.setKeyMap(MyWhoosh());
  });

  group('local action card visibility', () {
    test('keyboard/touch cards show for local target even when Local is disabled', () async {
      if (!isDesktop) return; // local control unavailable off-desktop
      await core.settings.setLastTarget(Target.thisDevice);
      core.settings.setLocalEnabled(false);

      expect(core.logic.showLocalControl, isTrue);
      expect(core.logic.showLocalKeyboardCard, isTrue);
      expect(core.logic.showLocalTouchCard, isTrue);
    });

    test('remote target: cards hidden unless the matching remote method is enabled', () async {
      await core.settings.setLastTarget(Target.otherDevice);
      core.settings.setLocalEnabled(false);
      core.settings.setRemoteControlEnabled(false);
      core.settings.setRemoteKeyboardControlEnabled(false);

      expect(core.logic.showLocalControl, isFalse);
      expect(core.logic.showLocalKeyboardCard, isFalse);
      expect(core.logic.showLocalTouchCard, isFalse);
    });

    test('remote target: keyboard card shows when remote keyboard control is enabled', () async {
      await core.settings.setLastTarget(Target.otherDevice);
      core.settings.setRemoteKeyboardControlEnabled(true);

      expect(core.logic.isRemoteKeyboardControlEnabled, isTrue);
      expect(core.logic.showLocalKeyboardCard, isTrue);
    });

    test('remote target: touch card shows when remote control is enabled', () async {
      await core.settings.setLastTarget(Target.otherDevice);
      core.settings.setRemoteControlEnabled(true);

      expect(core.logic.isRemoteControlEnabled, isTrue);
      expect(core.logic.showLocalTouchCard, isTrue);
    });
  });
}
