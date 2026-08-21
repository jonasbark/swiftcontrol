import 'dart:io';

import 'package:bike_control/gen/l10n.dart';
import 'package:bike_control/main.dart' show screenshotMode;
import 'package:bike_control/services/local_network_access.dart';
import 'package:bike_control/utils/requirements/local_network.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_network_permission/local_network_permission.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final calls = <String>[];
  late String outcome;

  setUp(() async {
    await AppLocalizations.load(const Locale('en'));
    calls.clear();
    outcome = 'granted';
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    LocalNetworkAccess.resetForTest();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      LocalNetworkPermission.channel,
      (call) async {
        calls.add(call.method);
        return call.method == 'check' ? outcome : null;
      },
    );
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    LocalNetworkAccess.resetForTest();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      LocalNetworkPermission.channel,
      null,
    );
  });

  test('is satisfied when the permission is granted', () async {
    expect(await LocalNetworkRequirement().getStatus(), isTrue);
  });

  test('is unsatisfied only on a positive denial', () async {
    outcome = 'denied';
    final requirement = LocalNetworkRequirement();
    expect(await requirement.getStatus(), isFalse);
    expect(requirement.status, isFalse);
  });

  test('stays satisfied when the probe cannot tell', () async {
    // No usable network is not the same as a denial; blocking here would break
    // setups that work.
    outcome = 'unknown';
    expect(await LocalNetworkRequirement().getStatus(), isTrue);
  });

  test('call opens settings and drops the cached answer', () async {
    outcome = 'denied';
    final requirement = LocalNetworkRequirement();
    await requirement.getStatus();
    expect(LocalNetworkAccess.cached, LocalNetworkStatus.denied);

    var updates = 0;
    await requirement.call(_NullContext(), () => updates++);

    expect(calls, contains('openSettings'));
    expect(LocalNetworkAccess.cached, isNull, reason: 'the user may have just flipped the toggle');
    expect(updates, 1);
  });

  test('carries a name and a description for the permission sheet', () {
    final requirement = LocalNetworkRequirement();
    expect(requirement.name, isNotEmpty);
    expect(requirement.description, isNotNull);
    // macOS users need the System Settings path; iOS users need theirs.
    expect(requirement.description, contains('Local Network'));
  });

  test('is suppressed in screenshot mode', () {
    // Marketing captures must not depend on the toggle state of whichever
    // machine runs them.
    screenshotMode = true;
    addTearDown(() => screenshotMode = false);
    expect(localNetworkRequirements(), isEmpty);
  });

  test('is supplied on Apple platforms and nowhere else', () {
    // Guarded on dart:io rather than debugDefaultTargetPlatformOverride, so
    // this asserts against the host running the suite.
    if (Platform.isIOS || Platform.isMacOS) {
      expect(localNetworkRequirements().single, isA<LocalNetworkRequirement>());
    } else {
      expect(localNetworkRequirements(), isEmpty);
    }
  });
}

/// [LocalNetworkRequirement.call] never touches its context — it delegates
/// straight to the platform channel — so a stub is enough.
class _NullContext implements BuildContext {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
