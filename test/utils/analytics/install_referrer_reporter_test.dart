import 'package:bike_control/utils/analytics/install_referrer_reporter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeSource implements InstallReferrerSource {
  _FakeSource(this._value, {this.throwOnRead = false});

  final String? _value;
  final bool throwOnRead;
  int reads = 0;

  @override
  Future<String?> read() async {
    reads++;
    if (throwOnRead) throw StateError('referrer unavailable');
    return _value;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<Map<String, dynamic>> sent;
  late SharedPreferences prefs;

  Future<void> setUpPrefs([Map<String, Object> initial = const {}]) async {
    SharedPreferences.setMockInitialValues(initial);
    prefs = await SharedPreferences.getInstance();
  }

  setUp(() async {
    sent = <Map<String, dynamic>>[];
    await setUpPrefs();
  });

  InstallReferrerReporter build(_FakeSource source) => InstallReferrerReporter(
    source: source,
    prefs: prefs,
    send: (body) async => sent.add(body),
  );

  test('reports the parsed UTMs alongside the raw referrer', () async {
    final source = _FakeSource(
      'utm_source=facebook&utm_medium=paid&utm_campaign=di2-launch-2026-08&utm_content=AD-DI2-EN-FEATURE',
    );

    await build(source).reportOnce();

    expect(sent, hasLength(1));
    expect(sent.single, {
      'eventType': 'app_install',
      'downloadPlatform': 'android',
      'referrerUrl':
          'utm_source=facebook&utm_medium=paid&utm_campaign=di2-launch-2026-08&utm_content=AD-DI2-EN-FEATURE',
      'utm_source': 'facebook',
      'utm_medium': 'paid',
      'utm_campaign': 'di2-launch-2026-08',
      'utm_content': 'AD-DI2-EN-FEATURE',
    });
  });

  test('still reports an organic install so paid and organic can be compared', () async {
    await build(_FakeSource('utm_source=google-play&utm_medium=organic')).reportOnce();

    expect(sent, hasLength(1));
    expect(sent.single['eventType'], 'app_install');
    expect(sent.single['utm_source'], 'google-play');
  });

  test('reports even when no referrer is available at all', () async {
    await build(_FakeSource(null)).reportOnce();

    expect(sent, hasLength(1));
    expect(sent.single['referrerUrl'], isNull);
    expect(sent.single.containsKey('utm_source'), isFalse);
  });

  test('marks itself done so a second launch does not report again', () async {
    final source = _FakeSource('utm_source=facebook');

    await build(source).reportOnce();
    await build(source).reportOnce();

    expect(sent, hasLength(1));
    expect(source.reads, 1, reason: 'the guard should short-circuit before reading');
    expect(prefs.getBool(InstallReferrerReporter.reportedKey), isTrue);
  });

  test('persists the raw referrer so RevenueCat attributes can be re-sent later', () async {
    // The Play referrer is readable only once, early. RevenueCat attributes
    // must be re-sent on later launches, so the raw value has to outlive the
    // one-shot read.
    await build(_FakeSource('utm_source=facebook&utm_campaign=di2-launch-2026-08')).reportOnce();

    expect(
      prefs.getString(InstallReferrerReporter.referrerKey),
      'utm_source=facebook&utm_campaign=di2-launch-2026-08',
    );
  });

  test('persists nothing when there is no referrer to persist', () async {
    await build(_FakeSource(null)).reportOnce();

    expect(prefs.getString(InstallReferrerReporter.referrerKey), isNull);
  });

  test('does not persist the referrer when sending fails', () async {
    final reporter = InstallReferrerReporter(
      source: _FakeSource('utm_source=facebook'),
      prefs: prefs,
      send: (_) async => throw StateError('network down'),
    );

    await expectLater(reporter.reportOnce(), throwsA(isA<StateError>()));
    expect(prefs.getString(InstallReferrerReporter.referrerKey), isNull);
  });

  test('does not mark itself done when sending fails, so it retries', () async {
    final reporter = InstallReferrerReporter(
      source: _FakeSource('utm_source=facebook'),
      prefs: prefs,
      send: (_) async => throw StateError('network down'),
    );

    await expectLater(reporter.reportOnce(), throwsA(isA<StateError>()));
    expect(prefs.getBool(InstallReferrerReporter.reportedKey), isNot(isTrue));
  });

  test('lets a source failure propagate rather than swallowing it', () async {
    final reporter = build(_FakeSource(null, throwOnRead: true));

    await expectLater(reporter.reportOnce(), throwsA(isA<StateError>()));
    expect(sent, isEmpty);
  });
}
