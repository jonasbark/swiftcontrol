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
/// Callers must give this widget a bounded width and a finite height — the
/// `Row`/`Flexible` layout below asserts if width is unbounded. It is
/// designed for a box around [_designHeight] (180px) tall, such as the
/// onboarding pager's hero; below that it degrades gracefully (see
/// [_designHeight]) but is not intended for arbitrarily tall boxes.
class ClickContours extends StatelessWidget {
  /// 0 = left side only, 1 = unlock with Zwift. Values outside are clamped.
  final double page;

  const ClickContours({super.key, required this.page});

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

  @override
  Widget build(BuildContext context) {
    final t = page.clamp(0.0, 1.0);
    final cs = Theme.of(context).colorScheme;
    // Same treatment ControllerCanvas gives these silhouettes: tint in dark
    // mode, leave the source art alone in light mode.
    final colorFilter = Theme.of(context).brightness == Brightness.dark
        ? ColorFilter.mode(cs.primary, BlendMode.srcIn)
        : null;

    return LayoutBuilder(
      builder: (context, constraints) {
        // Scale the absolute-pixel constants down when given less height
        // than the design was authored for (e.g. a small thumbnail), but
        // never scale them up beyond their authored size.
        final k = constraints.maxHeight.isFinite ? (constraints.maxHeight / _designHeight).clamp(0.0, 1.0) : 1.0;

        return Row(
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
                      blurRadius: _glowBlurRadius * k,
                      spreadRadius: _glowSpreadRadius * k,
                    ),
                  ],
                ),
                child: SvgPicture.asset(
                  'assets/contours/zwift_click_v2_left_side.svg',
                  fit: BoxFit.contain,
                  colorFilter: colorFilter,
                ),
              ),
            ),
            const SizedBox(width: 16),
            Flexible(
              child: Transform.translate(
                key: const ValueKey('click-contour-right-translate'),
                offset: Offset(_mutedOffset * k * (1 - t), 0),
                child: Transform.scale(
                  key: const ValueKey('click-contour-right-scale'),
                  scale: _mutedScale + (1 - _mutedScale) * t,
                  child: Opacity(
                    key: const ValueKey('click-contour-right-opacity'),
                    opacity: _mutedOpacity + (1 - _mutedOpacity) * t,
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
      },
    );
  }
}
