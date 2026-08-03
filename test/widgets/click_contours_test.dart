import 'package:bike_control/widgets/click_v2/click_contours.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

Opacity _rightPuckOpacity(WidgetTester tester) => tester.widget<Opacity>(
  find.byKey(const ValueKey('click-contour-right-opacity')),
);

Transform _rightPuckScale(WidgetTester tester) => tester.widget<Transform>(
  find.byKey(const ValueKey('click-contour-right-scale')),
);

Transform _rightPuckTranslate(WidgetTester tester) => tester.widget<Transform>(
  find.byKey(const ValueKey('click-contour-right-translate')),
);

double _leftPuckGlowAlpha(WidgetTester tester) {
  final box = tester.widget<DecoratedBox>(find.byKey(const ValueKey('click-contour-left-glow')));
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

  testWidgets('the right puck is faded out on the left-side-only page', (tester) async {
    await pumpAt(tester, 0);
    expect(_rightPuckOpacity(tester).opacity, closeTo(0.15, 0.001));
  });

  testWidgets('the right puck is fully visible on the unlock-with-Zwift page', (tester) async {
    await pumpAt(tester, 1);
    expect(_rightPuckOpacity(tester).opacity, closeTo(1.0, 0.001));
  });

  testWidgets('a half-swipe interpolates rather than snapping', (tester) async {
    await pumpAt(tester, 0.5);
    final opacity = _rightPuckOpacity(tester).opacity;
    expect(opacity, greaterThan(0.15));
    expect(opacity, lessThan(1.0));
  });

  testWidgets('page values outside 0..1 are clamped', (tester) async {
    await pumpAt(tester, -0.4);
    expect(_rightPuckOpacity(tester).opacity, closeTo(0.15, 0.001));

    await pumpAt(tester, 1.7);
    expect(_rightPuckOpacity(tester).opacity, closeTo(1.0, 0.001));
  });

  testWidgets('the right puck scale interpolates from muted to full size', (tester) async {
    // Transform.scale builds Matrix4.diagonal3Values(scale, scale, 1.0), so
    // storage[0] (m00) is the x-scale factor directly. getMaxScaleOnAxis()
    // isn't usable here — it maxes against the matrix's always-1.0 z entry,
    // which masks any scale below 1.
    await pumpAt(tester, 0);
    expect(_rightPuckScale(tester).transform.storage[0], closeTo(0.92, 0.001));

    await pumpAt(tester, 1);
    expect(_rightPuckScale(tester).transform.storage[0], closeTo(1.0, 0.001));
  });

  testWidgets('the right puck slides in from its outward offset at the pager size', (tester) async {
    // pumpAt uses a 400x200 box — at or above the 180px design height, so
    // the offset scale factor k is capped at 1.0 and these match the
    // unscaled design values exactly.
    await pumpAt(tester, 0);
    expect(_rightPuckTranslate(tester).transform.getTranslation().x, closeTo(14, 0.001));

    await pumpAt(tester, 1);
    expect(_rightPuckTranslate(tester).transform.getTranslation().x, closeTo(0, 0.001));
  });

  testWidgets('the left puck glow ring fades out as the right puck joins it', (tester) async {
    await pumpAt(tester, 0);
    expect(_leftPuckGlowAlpha(tester), closeTo(0.28, 0.001));

    await pumpAt(tester, 1);
    expect(_leftPuckGlowAlpha(tester), closeTo(0.0, 0.001));
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

    final dx = _rightPuckTranslate(tester).transform.getTranslation().x;
    expect(dx, greaterThan(0));
    expect(dx, lessThan(14));
    expect(dx, closeTo(40 / 180 * 14, 0.01));
  });

  testWidgets('the idle-timeout badge owns page 0 and the padlock owns page 1', (tester) async {
    await pumpAt(tester, 0);
    expect(
      tester.widget<Opacity>(find.byKey(const ValueKey('click-contour-idle-badge'))).opacity,
      closeTo(1.0, 0.001),
    );
    expect(
      tester.widget<Opacity>(find.byKey(const ValueKey('click-contour-lock-badge'))).opacity,
      closeTo(0.0, 0.001),
    );

    await pumpAt(tester, 1);
    expect(
      tester.widget<Opacity>(find.byKey(const ValueKey('click-contour-idle-badge'))).opacity,
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
}
