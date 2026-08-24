import 'package:bike_control/widgets/ui/colored_title.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

/// A single Help Center section: a header (icon + title) over a `Card` body,
/// staggered into view — fade+slide, 60 ms per [index] — as the page first
/// builds. Cheap by design: a single `TweenAnimationBuilder` per section, no
/// controllers to dispose.
class HelpCenterSectionCard extends StatelessWidget {
  final int index;
  final IconData icon;
  final String title;
  final Widget child;

  const HelpCenterSectionCard({
    super.key,
    required this.index,
    required this.icon,
    required this.title,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      key: ValueKey('help-center-section-anim-$index'),
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 220 + index * 60),
      curve: Curves.easeOut,
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, (1 - value) * 14),
            child: child,
          ),
        );
      },
      child: Card(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 12,
          children: [
            ColoredTitle(icon: icon, text: title),
            child,
          ],
        ),
      ),
    );
  }
}
