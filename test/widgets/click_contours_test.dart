import 'package:bike_control/widgets/click_v2/click_contours.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

Opacity _rightPuckOpacity(WidgetTester tester) => tester.widget<Opacity>(
  find.byKey(const ValueKey('click-contour-right-opacity')),
);

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
}
