import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:bike_control/bluetooth/devices/base_device.dart';
import 'package:bike_control/utils/keymap/buttons.dart';
import 'package:bike_control/utils/keymap/keymap.dart';
import 'package:bike_control/widgets/controller/trigger_assignment_popup.dart';
import 'package:bike_control/widgets/ui/small_progress_indicator.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

/// Which steer direction is active for [angle] given [threshold]. Mirrors
/// `GyroscopeSteering._applyPWMSteering`: positive ⇒ left, negative ⇒ right.
enum SteerSide { left, right, none }

SteerSide steerSideFor(double angle, double threshold) {
  if (angle > threshold) return SteerSide.left;
  if (angle < -threshold) return SteerSide.right;
  return SteerSide.none;
}

/// Animated steering-wheel gauge for the Phone-Steering device card footer.
/// The wheel rotates with the live tilt; a static top arc marks the ±threshold
/// trigger zones and glows on the actively-steering side. The left/right halves
/// are tap targets that open each steer button's remap editor.
class SteeringWheelGauge extends StatelessWidget {
  final ValueListenable<double> angle;
  final ValueListenable<bool> calibrated;
  final double threshold;

  /// Tilt (deg) mapped to full visual deflection of the wheel/arc.
  final double displayRange;

  final BaseDevice device;
  final ControllerButton leftButton;
  final ControllerButton rightButton;
  final Keymap? keymap;
  final VoidCallback? onUpdate;

  const SteeringWheelGauge({
    super.key,
    required this.angle,
    required this.calibrated,
    required this.threshold,
    required this.device,
    required this.leftButton,
    required this.rightButton,
    this.keymap,
    this.onUpdate,
    this.displayRange = 60,
  });

  bool get _canEdit => keymap != null && onUpdate != null;

  Future<void> _edit(BuildContext context, ControllerButton button) async {
    if (!_canEdit) return;
    await showTriggerAssignmentPopup(
      context: context,
      device: device,
      button: button,
      keymap: keymap!,
      onUpdate: onUpdate!,
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: 230 / Theme.of(context).scaling),
        child: AspectRatio(
          aspectRatio: 1.5,
          child: ValueListenableBuilder<bool>(
            valueListenable: calibrated,
            builder: (context, isCalibrated, _) {
              return ValueListenableBuilder<double>(
                valueListenable: angle,
                builder: (context, liveAngle, _) {
                  final side = isCalibrated ? steerSideFor(liveAngle, threshold) : SteerSide.none;
                  return Stack(
                    fit: StackFit.expand,
                    children: [
                      // Smoothly eases the wheel between sensor frames.
                      TweenAnimationBuilder<double>(
                        tween: Tween(end: liveAngle.clamp(-displayRange, displayRange)),
                        duration: const Duration(milliseconds: 120),
                        curve: Curves.easeOut,
                        builder: (context, animatedAngle, _) => CustomPaint(
                          painter: _SteeringWheelPainter(
                            angle: animatedAngle,
                            threshold: threshold,
                            displayRange: displayRange,
                            side: side,
                            dimmed: !isCalibrated,
                            wheelColor: cs.mutedForeground,
                            scaleColor: cs.border,
                            zoneColor: cs.mutedForeground.withValues(alpha: 0.12),
                            activeColor: cs.primary,
                          ),
                        ),
                      ),
                      // Tap-to-remap halves (transparent).
                      if (_canEdit)
                        Row(
                          children: [
                            Expanded(
                              child: GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: () => _edit(context, leftButton),
                              ),
                            ),
                            Expanded(
                              child: GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: () => _edit(context, rightButton),
                              ),
                            ),
                          ],
                        ),
                      // Numeric readout / calibrating hint.
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: IgnorePointer(
                          child: Center(
                            child: isCalibrated
                                ? Text(
                                    '${liveAngle.toStringAsFixed(0)}°  ·  ±${threshold.toStringAsFixed(0)}°',
                                  ).xSmall.muted
                                : Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      SmallProgressIndicator(),
                                      const SizedBox(width: 6),
                                      const Text('Calibrating…').xSmall.muted,
                                    ],
                                  ),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }
}

class _SteeringWheelPainter extends CustomPainter {
  final double angle; // clamped tilt, degrees
  final double threshold;
  final double displayRange;
  final SteerSide side;
  final bool dimmed;
  final Color wheelColor;
  final Color scaleColor;
  final Color zoneColor;
  final Color activeColor;

  _SteeringWheelPainter({
    required this.angle,
    required this.threshold,
    required this.displayRange,
    required this.side,
    required this.dimmed,
    required this.wheelColor,
    required this.scaleColor,
    required this.zoneColor,
    required this.activeColor,
  });

  // 12 o'clock is -pi/2 in Flutter canvas (x right, y down). Half of the arc's
  // total sweep, in radians. Positive tilt (left) maps to the LEFT of vertical.
  static const double _halfSweep = math.pi * 80 / 180; // 80° each side

  double _arcAngle(double tiltDeg) =>
      -math.pi / 2 - (tiltDeg / displayRange).clamp(-1.0, 1.0) * _halfSweep;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height * 0.62);
    final radius = math.min(size.width, size.height) * 0.30;
    final scaleR = radius * 1.45;
    final opacity = dimmed ? 0.4 : 1.0;

    // --- Static threshold-zone arcs (do not rotate) ---
    final zoneRect = Rect.fromCircle(center: center, radius: scaleR);
    final leftActive = side == SteerSide.left;
    final rightActive = side == SteerSide.right;
    final zonePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = radius * 0.16
      ..strokeCap = StrokeCap.round;

    // Left zone: tilt [threshold, displayRange]
    final lStart = _arcAngle(threshold);
    final lEnd = _arcAngle(displayRange);
    zonePaint.color = (leftActive ? activeColor : zoneColor).withValues(alpha: opacity);
    canvas.drawArc(zoneRect, lStart, lEnd - lStart, false, zonePaint);

    // Right zone: tilt [-threshold, -displayRange]
    final rStart = _arcAngle(-threshold);
    final rEnd = _arcAngle(-displayRange);
    zonePaint.color = (rightActive ? activeColor : zoneColor).withValues(alpha: opacity);
    canvas.drawArc(zoneRect, rStart, rEnd - rStart, false, zonePaint);

    // Center neutral tick at 12 o'clock.
    final tickPaint = Paint()
      ..color = scaleColor.withValues(alpha: opacity)
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    final up = _arcAngle(0);
    canvas.drawLine(
      center + Offset(math.cos(up), math.sin(up)) * (scaleR - radius * 0.12),
      center + Offset(math.cos(up), math.sin(up)) * (scaleR + radius * 0.12),
      tickPaint,
    );

    // --- Rotating steering wheel ---
    canvas.save();
    canvas.translate(center.dx, center.dy);
    // Positive tilt (left) rotates the wheel counter-clockwise (negative).
    final turn = -(angle / displayRange).clamp(-1.0, 1.0) * (math.pi * 0.6);
    canvas.rotate(turn);

    final rim = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = radius * 0.16
      ..color = wheelColor.withValues(alpha: opacity);
    canvas.drawCircle(Offset.zero, radius, rim);

    final spoke = Paint()
      ..strokeWidth = radius * 0.13
      ..strokeCap = StrokeCap.round
      ..color = wheelColor.withValues(alpha: opacity);
    // Top spoke (makes rotation legible) + lower-left + lower-right spokes.
    for (final a in [-math.pi / 2, math.pi / 6, math.pi * 5 / 6]) {
      canvas.drawLine(Offset.zero, Offset(math.cos(a), math.sin(a)) * radius, spoke);
    }
    final hub = Paint()..color = wheelColor.withValues(alpha: opacity);
    canvas.drawCircle(Offset.zero, radius * 0.20, hub);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _SteeringWheelPainter old) =>
      old.angle != angle ||
      old.threshold != threshold ||
      old.displayRange != displayRange ||
      old.side != side ||
      old.dimmed != dimmed ||
      old.wheelColor != wheelColor ||
      old.scaleColor != scaleColor ||
      old.zoneColor != zoneColor ||
      old.activeColor != activeColor;
}
