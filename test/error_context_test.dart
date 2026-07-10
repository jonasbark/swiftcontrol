import 'package:bike_control/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('isFatalErrorContext', () {
    // The persisted error log labels entries "App crashed" only for genuinely
    // uncaught errors caught by the app's top-level guards. Handled errors
    // funneled through record() from a try/catch (e.g. 'Retrofit Switch') must
    // NOT read as crashes — that mislabel made a handled BLE-advertise failure
    // look like an app crash in a support log.
    test('top-level uncaught guards are fatal', () {
      expect(isFatalErrorContext('Zone'), isTrue);
      expect(isFatalErrorContext('PlatformDispatcher'), isTrue);
      expect(isFatalErrorContext('Isolate'), isTrue);
    });

    test('handled try/catch contexts are not fatal', () {
      expect(isFatalErrorContext('Retrofit Switch'), isFalse);
      expect(isFatalErrorContext('Emulator start'), isFalse);
      expect(isFatalErrorContext('SettingsInit'), isFalse);
    });
  });
}
