import 'package:bike_control/widgets/click_v2/click_contours.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

// The muted puck is the LEFT one: page 0 is about the right side alone.
Opacity _mutedPuckOpacity(WidgetTester tester) => tester.widget<Opacity>(
  find.byKey(const ValueKey('click-contour-muted-opacity')),
);

Transform _mutedPuckScale(WidgetTester tester) => tester.widget<Transform>(
  find.byKey(const ValueKey('click-contour-muted-scale')),
);

Transform _mutedPuckTranslate(WidgetTester tester) => tester.widget<Transform>(
  find.byKey(const ValueKey('click-contour-muted-translate')),
);

double _leadPuckGlowAlpha(WidgetTester tester) {
  final box = tester.widget<DecoratedBox>(find.byKey(const ValueKey('click-contour-lead-glow')));
  final decoration = box.decoration as BoxDecoration;
  return decoration.boxShadow!.first.color.a;
}

void main() {
  // ShadcnApp, not MaterialApp: this widget renders inside the shadcn theme
  // everywhere it is used, and shadcn's Theme/ColorScheme are its own types.
  Future<void> pumpAt(WidgetTester tester, double page) async {
    await tester.pumpWidget(
      ShadcnApp(
        home: Scaffold(
          child: Center(child: SizedBox(width: 400, height: 200, child: ClickContours(page: page))),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('the left puck is faded out on the right-side-only page', (tester) async {
    await pumpAt(tester, 0);
    expect(_mutedPuckOpacity(tester).opacity, closeTo(0.15, 0.001));
  });

  testWidgets('the left puck is fully visible on the unlock-with-Zwift page', (tester) async {
    await pumpAt(tester, 1);
    expect(_mutedPuckOpacity(tester).opacity, closeTo(1.0, 0.001));
  });

  testWidgets('a half-swipe interpolates rather than snapping', (tester) async {
    await pumpAt(tester, 0.5);
    final opacity = _mutedPuckOpacity(tester).opacity;
    expect(opacity, greaterThan(0.15));
    expect(opacity, lessThan(1.0));
  });

  testWidgets('page values outside 0..1 are clamped', (tester) async {
    await pumpAt(tester, -0.4);
    expect(_mutedPuckOpacity(tester).opacity, closeTo(0.15, 0.001));

    await pumpAt(tester, 1.7);
    expect(_mutedPuckOpacity(tester).opacity, closeTo(1.0, 0.001));
  });

  testWidgets('the muted puck scale interpolates from muted to full size', (tester) async {
    // Transform.scale builds Matrix4.diagonal3Values(scale, scale, 1.0), so
    // storage[0] (m00) is the x-scale factor directly. getMaxScaleOnAxis()
    // isn't usable here — it maxes against the matrix's always-1.0 z entry,
    // which masks any scale below 1.
    await pumpAt(tester, 0);
    expect(_mutedPuckScale(tester).transform.storage[0], closeTo(0.92, 0.001));

    await pumpAt(tester, 1);
    expect(_mutedPuckScale(tester).transform.storage[0], closeTo(1.0, 0.001));
  });

  testWidgets('the muted puck slides in from its outward offset at the pager size', (tester) async {
    // pumpAt uses a 400x200 box — at or above the 180px design height, so
    // the offset scale factor k is capped at 1.0 and these match the
    // unscaled design values exactly.
    await pumpAt(tester, 0);
    expect(_mutedPuckTranslate(tester).transform.getTranslation().x, closeTo(-14, 0.001));

    await pumpAt(tester, 1);
    expect(_mutedPuckTranslate(tester).transform.getTranslation().x, closeTo(0, 0.001));
  });

  testWidgets('the right puck glow ring fades out as the left puck joins it', (tester) async {
    await pumpAt(tester, 0);
    expect(_leadPuckGlowAlpha(tester), closeTo(0.28, 0.001));

    await pumpAt(tester, 1);
    expect(_leadPuckGlowAlpha(tester), closeTo(0.0, 0.001));
  });

  testWidgets('the outward offset scales down proportionally in a small thumbnail', (tester) async {
    // A later task renders this widget as a small card thumbnail. The 14px
    // outward offset was authored against the 180px-tall pager hero, so in
    // a much shorter box it must shrink proportionally rather than staying
    // a flat 14px (which would be over half a puck's width at that size).
    await tester.pumpWidget(
      ShadcnApp(
        home: Scaffold(
          child: Center(child: SizedBox(width: 64, height: 40, child: ClickContours(page: 0))),
        ),
      ),
    );
    await tester.pump();

    final dx = _mutedPuckTranslate(tester).transform.getTranslation().x;
    expect(dx, lessThan(0));
    expect(dx, greaterThan(-14));
    expect(dx, closeTo(-40 / 180 * 14, 0.01));
  });

  testWidgets('the open padlock owns page 0 and the closed one owns page 1', (tester) async {
    await pumpAt(tester, 0);
    expect(
      tester.widget<Opacity>(find.byKey(const ValueKey('click-contour-free-badge'))).opacity,
      closeTo(1.0, 0.001),
    );
    expect(
      tester.widget<Opacity>(find.byKey(const ValueKey('click-contour-lock-badge'))).opacity,
      closeTo(0.0, 0.001),
    );

    await pumpAt(tester, 1);
    expect(
      tester.widget<Opacity>(find.byKey(const ValueKey('click-contour-free-badge'))).opacity,
      closeTo(0.0, 0.001),
    );
    expect(
      tester.widget<Opacity>(find.byKey(const ValueKey('click-contour-lock-badge'))).opacity,
      closeTo(1.0, 0.001),
    );
  });

  testWidgets('looping motion is suppressed when animations are disabled', (tester) async {
    await tester.pumpWidget(
      const ShadcnApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: Scaffold(
            child: Center(child: SizedBox(width: 400, height: 200, child: ClickContours(page: 0))),
          ),
        ),
      ),
    );
    await tester.pump();

    // A looping controller would leave the tester with pending frames forever;
    // pumpAndSettle returning proves nothing is looping.
    await tester.pumpAndSettle();
    expect(find.byType(ClickContours), findsOneWidget);
  });

  testWidgets('animate: false renders the silhouettes without either badge', (tester) async {
    await tester.pumpWidget(
      const ShadcnApp(
        home: Scaffold(
          child: Center(child: SizedBox(width: 400, height: 200, child: ClickContours(page: 1, animate: false))),
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(const ValueKey('click-contour-free-badge')), findsNothing);
    expect(find.byKey(const ValueKey('click-contour-lock-badge')), findsNothing);

    // The two silhouettes and their existing keyed widgets still render --
    // animate: false suppresses the badges and the loop, not the pucks.
    expect(find.byKey(const ValueKey('click-contour-muted-opacity')), findsOneWidget);
    expect(find.byKey(const ValueKey('click-contour-lead-glow')), findsOneWidget);
    expect(find.byKey(const ValueKey('click-contour-muted-scale')), findsOneWidget);
    expect(find.byKey(const ValueKey('click-contour-muted-translate')), findsOneWidget);
  });

  testWidgets('animate: false runs no looping controller', (tester) async {
    await tester.pumpWidget(
      const ShadcnApp(
        home: Scaffold(
          child: Center(child: SizedBox(width: 400, height: 200, child: ClickContours(page: 0, animate: false))),
        ),
      ),
    );
    await tester.pump();

    // As above: a looping controller would leave a pending frame forever, so
    // pumpAndSettle returning at all proves animate: false never starts one.
    await tester.pumpAndSettle();
    expect(find.byType(ClickContours), findsOneWidget);
  });
}
