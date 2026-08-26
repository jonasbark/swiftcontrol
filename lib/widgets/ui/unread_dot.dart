import 'package:shadcn_flutter/shadcn_flutter.dart';

/// Small destructive-colored dot with a background-colored halo border, used
/// to flag unread support-chat replies. Shared by `HelpButton`'s icon badge
/// and the Help Center's "Contact & community" chat row so both draw the
/// same dot instead of each keeping its own copy.
class UnreadDot extends StatelessWidget {
  final double size;

  const UnreadDot({super.key, this.size = 10});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.destructive,
        shape: BoxShape.circle,
        border: Border.all(
          color: Theme.of(context).colorScheme.background,
          width: 1.5,
        ),
      ),
    );
  }
}
