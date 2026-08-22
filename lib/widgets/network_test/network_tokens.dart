/// Design tokens for the network self-test screens.
///
/// Mirrors the "Network Troubleshooting" design's palette. Two deviations from
/// the source, both deliberate:
///
///  * The design ships Inter + JetBrains Mono. shadcn_flutter already bundles
///    GeistSans + GeistMono — the same neo-grotesque / geometric-mono pairing,
///    and what every other screen in the app is set in. Adding two webfonts to
///    make one page differ from the rest is a worse outcome than substituting.
///  * The design's `--primary-600` (#1e7ac8) is an approximation of the brand
///    blue; [BKColor.main] is the real one. Binding to the theme keeps this
///    page in step if the brand ever moves.
///
/// Status colours have no theme equivalent, so they are carried here — with a
/// dark variant, because the app themes both ways and the design only
/// specifies light.
library;

import 'package:shadcn_flutter/shadcn_flutter.dart';

class NetworkTokens {
  const NetworkTokens._({
    required this.ok,
    required this.okBg,
    required this.warn,
    required this.warnBg,
    required this.danger,
    required this.dangerBg,
    required this.hairline,
    required this.pageBg,
  });

  final Color ok;
  final Color okBg;
  final Color warn;
  final Color warnBg;
  final Color danger;
  final Color dangerBg;

  /// The design's `--ink-150`: the rule between rows, lighter than the card
  /// border so a list of rows doesn't read as a stack of boxes.
  final Color hairline;

  /// The design's `--ink-50` body wash, which is what separates the cards from
  /// the page behind them.
  final Color pageBg;

  static const _light = NetworkTokens._(
    ok: Color(0xFF1EA865),
    okBg: Color(0xFFE4F5EC),
    warn: Color(0xFFE8962A),
    warnBg: Color(0xFFFDF1DE),
    danger: Color(0xFFD43D4A),
    dangerBg: Color(0xFFFBE5E7),
    hairline: Color(0xFFEDEFF3),
    pageBg: Color(0xFFF8F9FB),
  );

  /// Same hues, re-seated for a dark surface: the foreground colours lift so
  /// they still carry on near-black, and the tints become low-alpha washes of
  /// themselves rather than the design's light backgrounds.
  static const _dark = NetworkTokens._(
    ok: Color(0xFF3DD68C),
    okBg: Color(0x2632D583),
    warn: Color(0xFFF5B544),
    warnBg: Color(0x26F5B544),
    danger: Color(0xFFF87078),
    dangerBg: Color(0x26F87078),
    hairline: Color(0xFF2A3344),
    pageBg: Color(0xFF15171C),
  );

  static NetworkTokens of(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? _dark : _light;
}
