import 'package:bike_control/utils/settings/settings.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prop/prop.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('key round-trips per serial', () async {
    final s = Settings();
    s.prefs = await SharedPreferences.getInstance();
    await s.setSramKey('SRAM 42', 'ab7c706800759ce024498cb423e0adc9');
    expect(s.getSramKey('SRAM 42'), 'ab7c706800759ce024498cb423e0adc9');
    expect(s.getSramKey('SRAM 99'), isNull);

    // Null removes an existing key (not stored as the literal "null").
    await s.setSramKey('SRAM 42', 'abc');
    await s.setSramKey('SRAM 42', null);
    expect(s.getSramKey('SRAM 42'), isNull);
  });

  test('backup and disabled flag round-trip', () async {
    final s = Settings();
    s.prefs = await SharedPreferences.getInstance();
    await s.setSramBackup('SRAM 42', {
      'd9050028': const SramReactionTrigger([0], [3]),
    });
    expect(s.getSramBackup('SRAM 42')!['d9050028']!.buttonMasks, [3]);

    // Absent backup returns null (not an empty map).
    expect(s.getSramBackup('SRAM 99'), isNull);

    expect(s.getSramShiftingDisabled('SRAM 42'), isFalse);
    await s.setSramShiftingDisabled('SRAM 42', true);
    expect(s.getSramShiftingDisabled('SRAM 42'), isTrue);
  });

  test('discovered buttons dedupe', () async {
    final s = Settings();
    s.prefs = await SharedPreferences.getInstance();
    await s.addSramButton('SRAM 42', 100, 1);
    await s.addSramButton('SRAM 42', 100, 1); // duplicate
    await s.addSramButton('SRAM 42', 200, 1);
    expect(s.getSramButtons('SRAM 42').length, 2);

    // Degraded -1 serial/mask round-trips through the "serial:mask" encoding.
    await s.addSramButton('SRAM 42', -1, 5);
    expect(s.getSramButtons('SRAM 42'), contains((serial: -1, mask: 5)));
  });
}
