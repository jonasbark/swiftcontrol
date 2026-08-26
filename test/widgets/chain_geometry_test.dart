import 'dart:math' as math;
import 'dart:ui';

import 'package:bike_control/widgets/drivetrain/chain_geometry.dart';
import 'package:flutter_test/flutter_test.dart';

/// The chain in the drivetrain view is solved, not drawn: if the belt solver is
/// wrong the chain leaves the sprockets or crosses itself, which no amount of
/// styling hides. These pin the properties a real chain has.
void main() {
  group('tangentBetween', () {
    test('touches both wheels at right angles to their radii', () {
      const a = Offset(74, 78);
      const b = Offset(216, 62);
      const ra = 36.0;
      const rb = 18.0;

      final run = tangentBetween(a, ra, 1, b, rb, 1);

      expect((run.from - a).distance, closeTo(ra, 0.001));
      expect((run.to - b).distance, closeTo(rb, 0.001));

      final along = run.to - run.from;
      final radiusA = run.from - a;
      final radiusB = run.to - b;
      expect(along.dx * radiusA.dx + along.dy * radiusA.dy, closeTo(0, 0.01));
      expect(along.dx * radiusB.dx + along.dy * radiusB.dy, closeTo(0, 0.01));
    });

    test('same-winding wheels get the external tangent, not the crossed one', () {
      const a = Offset(0, 0);
      const b = Offset(100, 0);
      final run = tangentBetween(a, 20, 1, b, 20, 1);

      // An external tangent between equal circles runs parallel to the line of
      // centres; a crossed one would pass between them and change sign.
      expect(run.from.dy.sign, run.to.dy.sign);
      expect(run.from.dy.abs(), closeTo(20, 0.001));
    });

    test('flipping one winding crosses the run between the wheels', () {
      const a = Offset(0, 0);
      const b = Offset(100, 0);
      final crossed = tangentBetween(a, 20, 1, b, 20, -1);

      expect(crossed.from.dy.sign, isNot(crossed.to.dy.sign));
    });
  });

  group('chainPath', () {
    test('wraps every wheel of the drivetrain', () {
      const rear = 20.0;
      final bounds = chainPath(36, rear).getBounds();

      // The loop has to reach around the chainring on the left and the tension
      // pulley hanging below the cassette on the right.
      expect(bounds.left, lessThan(kChainringCentre.dx - 30));
      expect(bounds.right, greaterThan(kCassetteCentre.dx + rear - 1));
      expect(bounds.bottom, greaterThan(tensionPulley(rear).dy));
    });

    test('stays inside the drawing box across the whole gear range', () {
      for (final gearCount in <int>[10, 12, 24]) {
        for (var gear = 1; gear <= gearCount; gear++) {
          final rear = rearRadiusFor(gear, gearCount);
          for (final front in <double>[kSingleRingRadius, 34 * kRadiusPerTooth, 50 * kRadiusPerTooth]) {
            final bounds = chainPath(front, rear).getBounds();
            expect(
              kDrivetrainBox.inflate(1).contains(bounds.topLeft) &&
                  kDrivetrainBox.inflate(1).contains(bounds.bottomRight),
              isTrue,
              reason: 'gear $gear/$gearCount, front $front escaped the box: $bounds',
            );
          }
        }
      }
    });

    test('re-routes when the chain moves to another cog', () {
      final easiest = chainPath(36, rearRadiusFor(1, 24)).getBounds();
      final hardest = chainPath(36, rearRadiusFor(24, 24)).getBounds();

      // Every gear has to move something visible — a 24-speed cassette is under
      // a pixel of radius per shift, so the cage travel is what carries it: the
      // 18 units the cog loses show up as ~15 units of chain dropping with it.
      expect((easiest.bottom - hardest.bottom).abs(), greaterThan(12));
    });

    test('each gear of a 24-speed lands somewhere new', () {
      final bottoms = <double>{
        for (var gear = 1; gear <= 24; gear++)
          double.parse(chainPath(36, rearRadiusFor(gear, 24)).getBounds().bottom.toStringAsFixed(2)),
      };
      expect(bottoms.length, 24);
    });
  });

  group('rearRadiusFor', () {
    test('gear 1 is the largest cog and the top gear the smallest', () {
      expect(rearRadiusFor(1, 24), kRearMaxRadius);
      expect(rearRadiusFor(24, 24), kRearMinRadius);
    });

    test('clamps out-of-range gears instead of drawing off the cassette', () {
      expect(rearRadiusFor(0, 12), kRearMaxRadius);
      expect(rearRadiusFor(99, 12), kRearMinRadius);
    });

    test('a single-speed sits on the largest cog', () {
      expect(rearRadiusFor(1, 1), kRearMaxRadius);
    });
  });

  group('dashedPath', () {
    Path line(double length) => Path()
      ..moveTo(0, 0)
      ..lineTo(length, 0);

    test('cuts a run into evenly spaced links', () {
      final dashes = dashedPath(line(100), on: 2, off: 6).computeMetrics().toList();
      expect(dashes.length, (100 / 8).ceil());
      expect(dashes.first.length, closeTo(2, 0.001));
    });

    test('sliding the phase moves the links along the run', () {
      final still = dashedPath(line(100), on: 2, off: 6).getBounds();
      final marched = dashedPath(line(100), on: 2, off: 6, phase: 4).getBounds();
      expect(marched.left, isNot(closeTo(still.left, 0.01)));
    });

    test('a full period of phase looks like no phase at all', () {
      final a = dashedPath(line(100), on: 2, off: 6, phase: 0).getBounds();
      final b = dashedPath(line(100), on: 2, off: 6, phase: 8).getBounds();
      expect(b.left, closeTo(a.left, 0.001));
    });

    test('an unset pattern draws nothing rather than looping forever', () {
      expect(dashedPath(line(100), on: 0, off: 0).computeMetrics().isEmpty, isTrue);
    });

    test('the chain loop keeps its links all the way round', () {
      final chain = chainPath(36, 20);
      final links = dashedPath(chain, on: kChainPitch * 0.3, off: kChainPitch * 0.7).computeMetrics().length;
      final perimeter = chain.computeMetrics().fold<double>(0, (sum, m) => sum + m.length);
      expect(links, closeTo(perimeter / kChainPitch, 2));
    });
  });

  test('the drawing box matches the design viewBox', () {
    expect(kDrivetrainBox, const Rect.fromLTWH(26, 28, 252, 110));
    expect(kDrivetrainBox.width / kDrivetrainBox.height, closeTo(252 / 110, 0.0001));
    expect(kTau, closeTo(math.pi * 2, 1e-12));
  });
}
