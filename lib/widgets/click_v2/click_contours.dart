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
class ClickContours extends StatelessWidget {
  /// 0 = left side only, 1 = unlock with Zwift. Values outside are clamped.
  final double page;

  const ClickContours({super.key, required this.page});

  static const double _mutedOpacity = 0.15;
  static const double _mutedScale = 0.92;
  static const double _mutedOffset = 14;

  @override
  Widget build(BuildContext context) {
    final t = page.clamp(0.0, 1.0);
    final cs = Theme.of(context).colorScheme;
    // Same treatment ControllerCanvas gives these silhouettes: tint in dark
    // mode, leave the source art alone in light mode.
    final colorFilter = Theme.of(context).brightness == Brightness.dark
        ? ColorFilter.mode(cs.primary, BlendMode.srcIn)
        : null;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Flexible(
          child: DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  // The glow marks the left puck as the one carrying the load
                  // on page 0, and fades out as the right puck joins it.
                  color: cs.primary.withValues(alpha: 0.28 * (1 - t)),
                  blurRadius: 34,
                  spreadRadius: 2,
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
            offset: Offset(_mutedOffset * (1 - t), 0),
            child: Transform.scale(
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
  }
}
