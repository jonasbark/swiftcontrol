/// The geometry behind the drivetrain schematic — a real belt solution rather
/// than a drawing that happens to look like one.
///
/// The chain is the closed external-tangent loop over four wheels (chainring,
/// active cog, guide pulley, tension pulley), so moving it to another cog
/// re-routes the whole loop the way it does on a bike, and the derailleur cage
/// swings as the chain climbs the stack. That is what makes a shift read as
/// motion instead of as a state swap.
///
/// Everything is expressed in the design's own coordinate box ([kDrivetrainBox],
/// the SVG viewBox the component was drawn in); the painter scales it to
/// whatever width it is handed.
library;

import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';

const double kTau = math.pi * 2;

/// The drawing box. Chainring, cassette, cage and the gear readout all fit
/// inside it at every radius, so nothing has to overflow.
const Rect kDrivetrainBox = Rect.fromLTWH(26, 28, 252, 110);

const Offset kChainringCentre = Offset(74, 78);
const Offset kCassetteCentre = Offset(216, 62);

const double kPulleyRadius = 7.5;

/// Largest cog (gear 1, easiest) and smallest (top gear).
const double kRearMaxRadius = 28;
const double kRearMinRadius = 10;

/// Radius per tooth — keeps a 34T and a 50T ring in true proportion.
const double kRadiusPerTooth = 0.78;

/// The neutral single ring drawn when front shifting is off.
const double kSingleRingRadius = 36;

/// Chain link pitch, i.e. the dash period of the marching inner line.
const double kChainPitch = 8;

/// The cage hangs off the active cog and swings down as the chain climbs the
/// stack, which is most of what makes a shift readable.
Offset guidePulley(double rearRadius) => Offset(kCassetteCentre.dx - 2, kCassetteCentre.dy + rearRadius + 12);

/// The tension pulley sits below and behind the guide — the derailleur's
/// S-bend, which is why the chain wraps the guide counter to the main loop.
Offset tensionPulley(double rearRadius) => Offset(kCassetteCentre.dx + 12, kCassetteCentre.dy + rearRadius + 32);

/// Rear cog radius for [gear] of [gearCount], gear 1 being the largest cog.
double rearRadiusFor(int gear, int gearCount) {
  final g = gear.clamp(1, math.max(1, gearCount));
  final t = gearCount > 1 ? (g - 1) / (gearCount - 1) : 0.0;
  return kRearMaxRadius - t * (kRearMaxRadius - kRearMinRadius);
}

/// One straight run of chain, from a contact point on one wheel to the contact
/// point on the next.
@immutable
class BeltTangent {
  const BeltTangent(this.from, this.to);

  final Offset from;
  final Offset to;
}

/// Chain travel direction at contact angle [t] on a wheel wound [w] — `1` with
/// the loop, `-1` against it (the S-bend pulley).
Offset _directionAt(double t, int w) => w == 1 ? Offset(-math.sin(t), math.cos(t)) : Offset(math.sin(t), -math.cos(t));

/// The chain run between two wheels, honouring each wheel's winding.
///
/// Signed radii pick the external versus the crossed pair; of those two, the
/// chain's is the one whose travel direction agrees with the winding at both
/// contact points.
BeltTangent tangentBetween(
  Offset a,
  double ra,
  int wa,
  Offset b,
  double rb,
  int wb,
) {
  final span = b - a;
  final d = span.distance == 0 ? 1.0 : span.distance;
  final theta = math.atan2(span.dy, span.dx);
  final ras = ra * wa;
  final rbs = rb * wb;
  final half = math.acos(((ras - rbs) / d).clamp(-1.0, 1.0));

  BeltTangent? best;
  var bestScore = double.negativeInfinity;
  for (final phi in <double>[theta + half, theta - half]) {
    final normal = Offset(math.cos(phi), math.sin(phi));
    final p1 = a + normal * ras;
    final p2 = b + normal * rbs;
    final run = p2 - p1;
    final u = run / (run.distance == 0 ? 1.0 : run.distance);
    final da = _directionAt(math.atan2(p1.dy - a.dy, p1.dx - a.dx), wa);
    final db = _directionAt(math.atan2(p2.dy - b.dy, p2.dx - b.dx), wb);
    final score = u.dx * da.dx + u.dy * da.dy + u.dx * db.dx + u.dy * db.dy;
    if (score > bestScore) {
      bestScore = score;
      best = BeltTangent(p1, p2);
    }
  }
  return best!;
}

class _Wheel {
  const _Wheel(this.centre, this.radius, this.winding);

  final Offset centre;
  final double radius;
  final int winding;
}

/// The closed chain loop: chainring → active cog → guide pulley (wound counter
/// to the loop) → tension pulley → back to the chainring.
Path chainPath(double frontRadius, double rearRadius) {
  final wheels = <_Wheel>[
    _Wheel(kChainringCentre, frontRadius, 1),
    _Wheel(kCassetteCentre, rearRadius, 1),
    _Wheel(guidePulley(rearRadius), kPulleyRadius, -1),
    _Wheel(tensionPulley(rearRadius), kPulleyRadius, 1),
  ];

  final runs = <BeltTangent>[
    for (var i = 0; i < wheels.length; i++)
      () {
        final a = wheels[i];
        final b = wheels[(i + 1) % wheels.length];
        return tangentBetween(a.centre, a.radius, a.winding, b.centre, b.radius, b.winding);
      }(),
  ];

  final path = Path()..moveTo(runs.first.from.dx, runs.first.from.dy);
  for (var i = 0; i < wheels.length; i++) {
    final j = (i + 1) % wheels.length;
    final wheel = wheels[j];
    final tIn = math.atan2(runs[i].to.dy - wheel.centre.dy, runs[i].to.dx - wheel.centre.dx);
    final tOut = math.atan2(runs[j].from.dy - wheel.centre.dy, runs[j].from.dx - wheel.centre.dx);
    // Dart's `%` on doubles is already non-negative, so this is the wrap angle
    // the chain actually sweeps around this wheel.
    final delta = (wheel.winding == 1 ? tOut - tIn : tIn - tOut) % kTau;
    path.lineTo(runs[i].to.dx, runs[i].to.dy);
    path.arcToPoint(
      runs[j].from,
      radius: Radius.circular(wheel.radius),
      largeArc: delta > math.pi,
      clockwise: wheel.winding == 1,
    );
  }
  return path..close();
}

/// [source] reduced to its dashes: [on] units drawn, [off] skipped, the pattern
/// slid back by [phase]. Flutter has no `stroke-dasharray`, and the chain's
/// marching links are the whole point, so we cut the path ourselves.
Path dashedPath(Path source, {required double on, required double off, double phase = 0}) {
  final period = on + off;
  final out = Path();
  if (period <= 0) return out;
  for (final metric in source.computeMetrics()) {
    for (var start = -(phase % period); start < metric.length; start += period) {
      final from = math.max(0.0, start);
      final to = math.min(metric.length, start + on);
      if (to > from) out.addPath(metric.extractPath(from, to), Offset.zero);
    }
  }
  return out;
}
