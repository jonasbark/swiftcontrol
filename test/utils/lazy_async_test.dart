// Backs the feedback-routing round's fix for a real regression: routing the
// "No difference"/"Not working" buttons through the Help Center made it an
// intermediate stop a rider can bounce off without ever opening the support
// chat, so eagerly starting debugText()'s (slow, mDNS-scanning) gather at
// tap time paid that cost for nothing. memoizeAsync defers the gather to
// first use and shares one result across every subsequent call — see
// proxy_device_details.dart's _routeToHelpCenter and
// help_center_support_context.dart.
import 'package:bike_control/utils/lazy_async.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('does not start the work just by wrapping it', () async {
    var calls = 0;
    memoizeAsync(() async {
      calls++;
      return calls;
    });

    // Give any stray microtask a chance to run before asserting nothing fired.
    await Future<void>.delayed(Duration.zero);

    expect(calls, 0, reason: 'constructing the wrapper must not itself run compute');
  });

  test('the first call starts the work; every later call reuses the same Future', () async {
    var calls = 0;
    final memoized = memoizeAsync(() async {
      calls++;
      return calls;
    });

    final first = memoized();
    final second = memoized();
    final third = memoized();

    expect(identical(first, second), isTrue, reason: 'a second call must not start a fresh computation');
    expect(identical(second, third), isTrue);
    expect(await first, 1);
    expect(await second, 1);
    expect(await third, 1);
    expect(calls, 1, reason: 'compute must run exactly once no matter how many times the wrapper is called');
  });

  test('two independently-wrapped computations do not share state', () async {
    var calls = 0;
    Future<int> compute() async => ++calls;

    final a = memoizeAsync(compute);
    final b = memoizeAsync(compute);

    expect(await a(), 1);
    expect(await b(), 2);
  });
}
