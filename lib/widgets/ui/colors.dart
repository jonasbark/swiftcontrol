import 'package:shadcn_flutter/shadcn_flutter.dart';

class BKColor {
  static const Color main = Color(0xFF0E74B7);
  static const Color mainEnd = Color(0xFF0E9297);
  static const Color background = Color(0xFFAACCDB);
  static const Color backgroundLight = Color(0xFFF2F9FF);
}

/// The brand blue, picked out against the current theme.
///
/// `colorScheme.primary` is the brand colour in light mode but a near-white in
/// the dark slate scheme, where it would be indistinguishable from foreground —
/// so dark mode gets a lifted blue instead.
Color bkAccent(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark ? const Color(0xFF4DA9E8) : Theme.of(context).colorScheme.primary;

/// One step firmer than `colorScheme.border` — the design's `border-strong`,
/// for hairlines that have to stay readable against an inset fill.
Color bkStrongBorder(BuildContext context) {
  final cs = Theme.of(context).colorScheme;
  return Color.lerp(cs.border, cs.mutedForeground, 0.45)!;
}
