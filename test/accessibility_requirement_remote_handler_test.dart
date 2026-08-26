import 'package:bike_control/gen/l10n.dart';
import 'package:bike_control/utils/actions/base_actions.dart';
import 'package:bike_control/utils/core.dart';
import 'package:bike_control/utils/requirements/android.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await AppLocalizations.load(const Locale('en'));
    SharedPreferences.setMockInitialValues({});
    core.settings.prefs = await SharedPreferences.getInstance();
  });

  // Regression: on Android, connecting BikeControl to a trainer app on another
  // device makes core.actionHandler a RemoteActions, not an AndroidActions.
  // The Network Troubleshooting "enable Local control" fix calls
  // AccessibilityRequirement.getStatus() regardless of the active handler, and
  // the blind cast `core.actionHandler as AndroidActions` threw a TypeError
  // ("type 'RemoteActions' is not a subtype of type 'AndroidActions'").
  test('getStatus returns false without throwing when the handler is not AndroidActions', () async {
    core.actionHandler = StubActions(); // stands in for any non-AndroidActions handler
    final requirement = AccessibilityRequirement();

    expect(await requirement.getStatus(), isFalse);
    expect(requirement.status, isFalse);
  });
}
