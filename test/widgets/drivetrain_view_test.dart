import 'package:bike_control/widgets/drivetrain/drivetrain_view.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

/// The drivetrain animates off a raw [Ticker], so what these guard is when it
/// runs: a chain marching for a bike nobody is pedalling burns frames on the
/// home screen forever, and would hang every `pumpAndSettle` that renders it.
void main() {
  Future<void> show(
    WidgetTester tester,
    Widget child, {
    bool reduceMotion = false,
  }) async {
    await tester.pumpWidget(
      ShadcnApp(
        debugShowCheckedModeBanner: false,
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: reduceMotion),
          child: SizedBox(width: 400, child: child),
        ),
      ),
    );
  }

  testWidgets('a parked drivetrain schedules no frames', (tester) async {
    await show(tester, const DrivetrainView(gear: 12, gearCount: 24, moving: false));
    await tester.pumpAndSettle();
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('pedalling keeps the chain marching', (tester) async {
    await show(tester, const DrivetrainView(gear: 12, gearCount: 24, moving: true, cadence: 90));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    expect(tester.binding.hasScheduledFrame, isTrue);
  });

  testWidgets('reduced motion stops the march', (tester) async {
    await show(
      tester,
      const DrivetrainView(gear: 12, gearCount: 24, moving: true, cadence: 90),
      reduceMotion: true,
    );
    await tester.pumpAndSettle();
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('stopping pedalling parks the drivetrain again', (tester) async {
    await show(tester, const DrivetrainView(gear: 12, gearCount: 24, moving: true, cadence: 90));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    expect(tester.binding.hasScheduledFrame, isTrue);

    await show(tester, const DrivetrainView(gear: 12, gearCount: 24, moving: false));
    await tester.pumpAndSettle();
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('a shift runs the ease and the landing ripple, then settles', (tester) async {
    await show(tester, const DrivetrainView(gear: 12, gearCount: 24, moving: false));
    await tester.pumpAndSettle();

    await show(tester, const DrivetrainView(gear: 13, gearCount: 24, moving: false));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    expect(tester.binding.hasScheduledFrame, isTrue, reason: 'the shift should be travelling');

    // The ripple outlives the 260 ms ease, so the ticker has to survive it too.
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.binding.hasScheduledFrame, isTrue, reason: 'the ripple should still be running');

    await tester.pumpAndSettle();
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('an out-of-range gear draws rather than throws', (tester) async {
    await show(tester, const DrivetrainView(gear: 99, gearCount: 12, moving: false));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    // Announced as the cog it is drawn on, not as the number it was handed.
    expect(find.bySemanticsLabel('12 / 12'), findsOneWidget);
  });

  testWidgets('front shifting names the ring it is on', (tester) async {
    await show(
      tester,
      const DrivetrainView(
        gear: 3,
        gearCount: 12,
        frontShift: true,
        largeRingActive: true,
        largeChainringTeeth: 50,
        moving: false,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('3 / 12 · 50T'), findsOneWidget);
  });

  group('the panel inset', () {
    Rect drawing(WidgetTester tester) => Rect.fromPoints(
      tester.getTopLeft(find.byType(AspectRatio)),
      tester.getBottomRight(find.byType(AspectRatio)),
    );

    testWidgets('framed: the drawing is inset from the panel edge', (tester) async {
      await show(tester, const DrivetrainView(gear: 12, gearCount: 24, moving: false));
      await tester.pumpAndSettle();
      final box = Rect.fromPoints(
        tester.getTopLeft(find.byType(DrivetrainView)),
        tester.getBottomRight(find.byType(DrivetrainView)),
      );
      expect(drawing(tester).left, greaterThan(box.left));
      expect(drawing(tester).right, lessThan(box.right));
    });

    testWidgets('unframed: the caller owns the inset, so we add none', (tester) async {
      await show(tester, const DrivetrainView(gear: 12, gearCount: 24, moving: false, framed: false));
      await tester.pumpAndSettle();
      final box = Rect.fromPoints(
        tester.getTopLeft(find.byType(DrivetrainView)),
        tester.getBottomRight(find.byType(DrivetrainView)),
      );
      // Padding here would be doubled up on the caller's own, and every pixel
      // of it comes off the drawing — which on a phone is the whole card.
      expect(drawing(tester), box);
    });
  });
}
