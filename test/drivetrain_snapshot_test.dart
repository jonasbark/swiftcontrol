@Tags(['screenshots'])
library;

import 'dart:typed_data';
import 'dart:ui' show ImageByteFormat;

import 'package:bike_control/widgets/drivetrain/drivetrain_view.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import 'widget_snapshot.dart';

/// Renders the drivetrain in the states the design's own card demos. Run:
/// `flutter test --run-skipped test/drivetrain_snapshot_test.dart`
///
/// The captions are not decoration: `loadAssets()` finds fonts by walking the
/// `Text` widgets in the tree, and the readouts inside the drivetrain are
/// painted rather than laid out — without a real `Text` alongside them they
/// come out as Ahem boxes in the capture (never in the app, which loads the
/// whole font manifest at startup).
Future<void> main() async {
  await ensureSnapshotHarness();

  Widget labelled(String caption, Widget child) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(caption).xSmall.muted,
      const Gap(4),
      child,
      const Gap(14),
    ],
  );

  testWidgets('DrivetrainView states → PNG', (tester) async {
    await captureWidget(
      tester,
      name: 'drivetrain_states',
      width: 400,
      builder: (context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          labelled('gear 12 of 24', const DrivetrainView(gear: 12, gearCount: 24, moving: false)),
          labelled('gear 1 — largest cog', const DrivetrainView(gear: 1, gearCount: 24, moving: false)),
          labelled('gear 24 — smallest cog', const DrivetrainView(gear: 24, gearCount: 24, moving: false)),
          labelled(
            'front shifting, big ring',
            const DrivetrainView(
              gear: 12,
              gearCount: 24,
              frontShift: true,
              largeRingActive: true,
              moving: false,
            ),
          ),
          labelled(
            '12-speed, not connected',
            const DrivetrainView(gear: 6, gearCount: 12, moving: false, dim: true),
          ),
        ],
      ),
    );
  });

  testWidgets('DrivetrainView dark → PNG', (tester) async {
    await captureWidget(
      tester,
      name: 'drivetrain_dark',
      width: 400,
      brightness: Brightness.dark,
      builder: (context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          labelled('gear 12 of 24', const DrivetrainView(gear: 12, gearCount: 24, moving: false)),
          labelled(
            'front shifting, small ring',
            const DrivetrainView(gear: 3, gearCount: 12, frontShift: true, moving: false),
          ),
        ],
      ),
    );
  });

  /// The one thing a still capture cannot show. Lives here rather than beside
  /// the other behaviour tests because `toImage()` needs the integration
  /// binding this harness installs — under the plain test binding it never
  /// completes.
  testWidgets('the chain visibly moves while pedalling and holds still when not', (tester) async {
    final boundary = GlobalKey();
    Future<void> render({required bool moving}) => tester.pumpWidget(
      ShadcnApp(
        debugShowCheckedModeBanner: false,
        home: RepaintBoundary(
          key: boundary,
          child: SizedBox(
            width: 400,
            child: DrivetrainView(gear: 12, gearCount: 24, moving: moving, cadence: 90),
          ),
        ),
      ),
    );

    Future<Uint8List> frame() async {
      final render = boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await render.toImage();
      final bytes = await image.toByteData(format: ImageByteFormat.rawRgba);
      image.dispose();
      return bytes!.buffer.asUint8List();
    }

    await render(moving: true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    final a = await frame();
    await tester.pump(const Duration(milliseconds: 100));
    final b = await frame();
    expect(a, isNot(equals(b)), reason: 'the chain should have marched between frames');

    await render(moving: false);
    await tester.pumpAndSettle();
    final c = await frame();
    await tester.pump(const Duration(milliseconds: 100));
    final d = await frame();
    expect(c, equals(d), reason: 'a parked drivetrain should not redraw itself differently');
  });
}
