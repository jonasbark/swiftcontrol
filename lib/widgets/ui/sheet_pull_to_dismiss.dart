import 'package:shadcn_flutter/shadcn_flutter.dart';

/// Bridges the gap shadcn's drawers leave for scrollable content: the
/// drawer's dismiss gesture is a raw vertical-drag GestureDetector, so any
/// inner scrollable wins the gesture arena and swipe-to-close only works on
/// the drag-handle strip. Wrapping the sheet content in this restores the
/// natural gesture — pulling down past the scrollable's top closes the sheet
/// (covers both bouncing physics, via negative pixels, and clamping physics,
/// via the overscroll notification).
class SheetPullToDismiss extends StatefulWidget {
  const SheetPullToDismiss({super.key, required this.child});
  final Widget child;

  @override
  State<SheetPullToDismiss> createState() => _SheetPullToDismissState();
}

class _SheetPullToDismissState extends State<SheetPullToDismiss> {
  static const double _threshold = 90;
  bool _closing = false;
  double _pulled = 0;

  void _close() {
    if (_closing) return;
    _closing = true;
    closeDrawer(context);
  }

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        if (n.metrics.axis != Axis.vertical) return false;
        if (n is ScrollEndNotification || n.metrics.extentBefore > 0) {
          _pulled = 0;
          return false;
        }
        // Clamping physics (Android/desktop): downward drags past the top
        // surface as negative overscrolls — accumulate them so a stray
        // pixel of overscroll doesn't dismiss the sheet.
        if (n is OverscrollNotification && n.overscroll < 0 && n.dragDetails != null) {
          _pulled += -n.overscroll;
          if (_pulled > _threshold) _close();
        }
        // Bouncing physics (iOS): the position itself goes negative.
        if (n is ScrollUpdateNotification && n.metrics.pixels < -_threshold && n.dragDetails != null) {
          _close();
        }
        return false;
      },
      child: widget.child,
    );
  }
}
