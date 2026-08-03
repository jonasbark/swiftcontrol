import 'dart:math' as math;

import 'package:flutter_svg/flutter_svg.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

/// The two Zwift Click V2 pucks side by side, with the right one fading in as
/// the onboarding pager moves from "left side only" (page 0) to "unlock with
/// Zwift" (page 1).
///
/// Takes a fractional [page] rather than owning a PageController so a swipe
/// scrubs the transition continuously instead of snapping at the page
/// boundary — and so the widget can be driven by a plain animation when the
/// flow is reopened for review.
///
/// When [animate] is true (the default), a small badge under each puck
/// cross-fades with [page] to explain that option's trade-off: an idle-pulse
/// pill on page 0 (the left-only mode drops the connection when idle, then
/// reconnects on its own) and a padlock on page 1 (Zwift's 24-hour unlock).
/// Both badges include a looping flourish — a pulse ripple and a sweep ring,
/// respectively — that is suppressed when the platform requests reduced
/// motion. Pass `animate: false` to render this as a static thumbnail (no
/// loop, no badges) — see the onboarding card's 64x40 preview.
///
/// Callers must give this widget a bounded width and a finite height — the
/// `Row`/`Flexible` layout below asserts if width is unbounded. It is
/// designed for a box around [_designHeight] (180px) tall, such as the
/// onboarding pager's hero; below that it degrades gracefully (see
/// [_designHeight]) but is not intended for arbitrarily tall boxes.
class ClickContours extends StatefulWidget {
  /// 0 = left side only, 1 = unlock with Zwift. Values outside are clamped.
  final double page;

  /// Whether to run the looping badge flourishes and render the badges at
  /// all. False for static thumbnail use (e.g. a small device-preview card),
  /// where a sweeping padlock would be cramped and distracting.
  final bool animate;

  const ClickContours({super.key, required this.page, this.animate = true});

  static const double _mutedOpacity = 0.15;
  static const double _mutedScale = 0.92;

  // The absolute pixel values below (glow blur/spread, right-puck offset)
  // were authored against the onboarding pager's 180px-tall hero box. A
  // later task reuses this widget as a much smaller card thumbnail, where
  // these same absolute pixels would overwhelm the art (e.g. a 34px blur in
  // a ~40px-tall thumbnail). _designHeight lets us scale them down
  // proportionally to whatever height the widget is actually given, while
  // leaving the look unchanged at 180px or taller.
  static const double _designHeight = 180;
  static const double _mutedOffset = 14;
  static const double _glowBlurRadius = 34;
  static const double _glowSpreadRadius = 2;

  /// How far the left puck dims at the peak of the idle-timeout pulse.
  static const double _idleDip = 0.45;

  @override
  State<ClickContours> createState() => _ClickContoursState();
}

/// Shapes one loop of the shared controller into a brief dip-and-recover
/// sitting mostly at rest — used for both the left puck's own dimming and
/// the idle badge's ripple, so the two stay in phase with each other.
final Animatable<double> _idlePulseShape = TweenSequence<double>([
  TweenSequenceItem(tween: ConstantTween(0.0), weight: 55),
  TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.0).chain(CurveTween(curve: Curves.easeInOut)), weight: 12),
  TweenSequenceItem(tween: ConstantTween(1.0), weight: 10),
  TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.0).chain(CurveTween(curve: Curves.easeInOut)), weight: 13),
  TweenSequenceItem(tween: ConstantTween(0.0), weight: 10),
]);

class _ClickContoursState extends State<ClickContours> with SingleTickerProviderStateMixin {
  late final AnimationController _loop = AnimationController(vsync: this, duration: const Duration(milliseconds: 2600));

  bool get _shouldLoop => widget.animate && !MediaQuery.of(context).disableAnimations;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Looping must never run under disableAnimations: a perpetually pending
    // frame makes pumpAndSettle hang and burns battery on the overview page.
    if (_shouldLoop && !_loop.isAnimating) {
      _loop.repeat();
    } else if (!_shouldLoop && _loop.isAnimating) {
      _loop.stop();
      _loop.value = 0;
    }
  }

  @override
  void dispose() {
    _loop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.page.clamp(0.0, 1.0);
    final cs = Theme.of(context).colorScheme;
    // Same treatment ControllerCanvas gives these silhouettes: tint in dark
    // mode, leave the source art alone in light mode.
    final colorFilter = Theme.of(context).brightness == Brightness.dark
        ? ColorFilter.mode(cs.primary, BlendMode.srcIn)
        : null;
    // Constant null (not just a stopped controller) when looping shouldn't
    // run, so the badges and the puck dimming can render their exact resting
    // state without depending on a controller's momentary value.
    final loopAnim = _shouldLoop ? _loop : null;

    return LayoutBuilder(
      builder: (context, constraints) {
        // Scale the absolute-pixel constants down when given less height
        // than the design was authored for (e.g. a small thumbnail), but
        // never scale them up beyond their authored size.
        final k = constraints.maxHeight.isFinite ? (constraints.maxHeight / ClickContours._designHeight).clamp(0.0, 1.0) : 1.0;

        final leftPuck = SvgPicture.asset(
          'assets/contours/zwift_click_v2_left_side.svg',
          fit: BoxFit.contain,
          colorFilter: colorFilter,
        );

        final row = Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Flexible(
              child: DecoratedBox(
                key: const ValueKey('click-contour-left-glow'),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      // The glow marks the left puck as the one carrying the load
                      // on page 0, and fades out as the right puck joins it.
                      color: cs.primary.withValues(alpha: 0.28 * (1 - t)),
                      blurRadius: ClickContours._glowBlurRadius * k,
                      spreadRadius: ClickContours._glowSpreadRadius * k,
                    ),
                  ],
                ),
                child: loopAnim == null
                    ? leftPuck
                    : AnimatedBuilder(
                        animation: loopAnim,
                        builder: (context, child) {
                          final pulse = _idlePulseShape.transform(loopAnim.value);
                          return Opacity(opacity: 1 - ClickContours._idleDip * pulse, child: child);
                        },
                        child: leftPuck,
                      ),
              ),
            ),
            const SizedBox(width: 16),
            Flexible(
              child: Transform.translate(
                key: const ValueKey('click-contour-right-translate'),
                offset: Offset(ClickContours._mutedOffset * k * (1 - t), 0),
                child: Transform.scale(
                  key: const ValueKey('click-contour-right-scale'),
                  scale: ClickContours._mutedScale + (1 - ClickContours._mutedScale) * t,
                  child: Opacity(
                    key: const ValueKey('click-contour-right-opacity'),
                    opacity: ClickContours._mutedOpacity + (1 - ClickContours._mutedOpacity) * t,
                    child: SvgPicture.asset(
                      'assets/contours/zwift_click_v2_right_side.svg',
                      fit: BoxFit.contain,
                      colorFilter: colorFilter,
                    ),
                  ),
                ),
              ),
            ),
          ],
        );

        if (!widget.animate) return row;

        return Stack(
          children: [
            row,
            Opacity(
              key: const ValueKey('click-contour-idle-badge'),
              opacity: 1 - t,
              child: _IdleBadge(pulse: loopAnim, scale: k),
            ),
            Opacity(
              key: const ValueKey('click-contour-lock-badge'),
              opacity: t,
              child: _LockBadge(sweep: loopAnim, settle: t, scale: k),
            ),
          ],
        );
      },
    );
  }
}

/// Page-0 badge: a small pill under the left puck that loops through a dip
/// and recovery to sell "drops out, then reconnects on its own" at a glance.
/// [pulse] is null when looping shouldn't run (reduced motion, or the whole
/// widget is a static thumbnail), in which case the badge renders at rest.
class _IdleBadge extends StatelessWidget {
  final Animation<double>? pulse;
  final double scale;

  const _IdleBadge({required this.pulse, required this.scale});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final k = scale;

    Widget pillAt(double pulseValue) {
      return SizedBox(
        width: 40 * k,
        height: 26 * k,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // The ripple: expands and fades as the puck dims, so the two
            // read as one "losing the connection" beat.
            Container(
              width: 18 * k * (1 + 0.8 * pulseValue),
              height: 18 * k * (1 + 0.8 * pulseValue),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: cs.primary.withValues(alpha: 0.5 * (1 - pulseValue)), width: 1.2 * k),
              ),
            ),
            Container(
              padding: EdgeInsets.symmetric(horizontal: 6 * k, vertical: 2 * k),
              decoration: BoxDecoration(
                color: cs.card,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: cs.border),
              ),
              child: Icon(Icons.autorenew, size: 12 * k, color: cs.mutedForeground),
            ),
          ],
        ),
      );
    }

    final content = pulse == null
        ? pillAt(0.0)
        : AnimatedBuilder(animation: pulse!, builder: (context, _) => pillAt(_idlePulseShape.transform(pulse!.value)));

    return Align(alignment: const Alignment(-0.55, 0.85), child: content);
  }
}

/// Page-1 badge: a padlock between the pucks whose shackle lifts once the
/// page settles on the Zwift-unlock option, wrapped in a ring that sweeps
/// once through 360° per loop of [sweep]. [sweep] is null when looping
/// shouldn't run, in which case the ring renders as a plain static circle.
class _LockBadge extends StatelessWidget {
  final Animation<double>? sweep;
  final double settle;
  final double scale;

  const _LockBadge({required this.sweep, required this.settle, required this.scale});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final k = scale;
    final size = 34.0 * k;
    // The shackle only lifts once the swipe has essentially committed to
    // this page, so it doesn't flicker open mid-drag.
    final lift = ((settle - 0.9) / 0.1).clamp(0.0, 1.0);

    Widget ringAt(double progress) {
      return CustomPaint(size: Size(size, size), painter: _SweepRingPainter(color: cs.primary, progress: progress));
    }

    final ring = sweep == null ? ringAt(0.0) : AnimatedBuilder(animation: sweep!, builder: (context, _) => ringAt(sweep!.value));

    return Align(
      alignment: Alignment.center,
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            ring,
            Transform.translate(
              offset: Offset(0, -3 * k * lift),
              child: Icon(lift > 0.5 ? Icons.lock_open : Icons.lock_outline, size: 16 * k, color: cs.primary),
            ),
          ],
        ),
      ),
    );
  }
}

class _SweepRingPainter extends CustomPainter {
  final Color color;

  /// 0..1, one full lap of the ring per loop cycle.
  final double progress;

  _SweepRingPainter({required this.color, required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    if (size.shortestSide <= 0) return;
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2 - 1;

    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = color.withValues(alpha: 0.18)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );

    const arcLength = math.pi / 2;
    final start = -math.pi / 2 + progress * 2 * math.pi;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      start,
      arcLength,
      false,
      Paint()
        ..color = color.withValues(alpha: 0.85)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant _SweepRingPainter oldDelegate) => oldDelegate.progress != progress || oldDelegate.color != color;
}
