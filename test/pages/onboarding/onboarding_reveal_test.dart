import 'package:bike_control/pages/onboarding/widgets/onboarding_reveal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

List<OnboardingReveal> revealsIn(List<Widget> wrapped) => wrapped.whereType<OnboardingReveal>().toList();

void main() {
  group('onboardingReveal staggering', () {
    test('each item is delayed one interval further than the last', () {
      final wrapped = onboardingReveal([const Text('a'), const Text('b'), const Text('c')]);
      expect(
        revealsIn(wrapped).map((r) => r.delay),
        [Duration.zero, OnboardingReveal.interval, OnboardingReveal.interval * 2],
      );
    });

    test('gaps pass through untouched, so the layout is settled from frame one', () {
      final wrapped = onboardingReveal([const Text('a'), const Gap(8), const Text('b')]);

      expect(wrapped[1], isA<Gap>());
      // The gap does not consume a stagger slot — the two texts stay adjacent
      // in the cadence rather than leaving a hole in it.
      expect(revealsIn(wrapped).map((r) => r.delay), [Duration.zero, OnboardingReveal.interval]);
    });

    test('an offset delay shifts the whole column without changing its rhythm', () {
      final wrapped = onboardingReveal(
        [const Text('a'), const Text('b')],
        delay: const Duration(milliseconds: 200),
      );
      expect(
        revealsIn(wrapped).map((r) => r.delay),
        [const Duration(milliseconds: 200), const Duration(milliseconds: 200) + OnboardingReveal.interval],
      );
    });

    // A long device list must not push its last entry a second and a half out —
    // a rider reaching for it would watch it move.
    test('the delay stops growing past the cap', () {
      final wrapped = onboardingReveal(List.generate(20, (i) => Text('$i')));
      final delays = revealsIn(wrapped).map((r) => r.delay).toList();

      final capped = OnboardingReveal.interval * OnboardingReveal.maxStaggered;
      expect(delays.last, capped);
      expect(delays.every((d) => d <= capped), isTrue);
    });

    test('an empty column stays empty', () {
      expect(onboardingReveal(const []), isEmpty);
    });
  });

  group('OnboardingReveal rendering', () {
    testWidgets('renders its child statically when animations are disabled', (tester) async {
      await tester.pumpWidget(
        const MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: OnboardingReveal(delay: Duration(milliseconds: 400), child: Text('hello')),
          ),
        ),
      );

      // No animation to wait out: the child is simply there, at full opacity.
      expect(find.text('hello'), findsOneWidget);
      expect(find.byType(TweenAnimationBuilder<double>), findsNothing);
    });

    testWidgets('animates in, and settles', (tester) async {
      await tester.pumpWidget(
        const MediaQuery(
          data: MediaQueryData(),
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: OnboardingReveal(child: Text('hello')),
          ),
        ),
      );

      await tester.pump();
      final opacity = tester.widget<Opacity>(find.byType(Opacity).first);
      expect(opacity.opacity, lessThan(1));

      await tester.pumpAndSettle();
      expect(tester.widget<Opacity>(find.byType(Opacity).first).opacity, 1);
    });
  });
}
