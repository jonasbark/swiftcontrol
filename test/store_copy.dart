// The marketing copy and brand styling the store boards are drawn with.
//
// Deliberately NOT in the app's ARB files. These are advertising claims, not
// app copy: they have their own review, their own lifecycle and their own
// constraint (see [kSceneHeadlineMaxChars]). Mixing them into the string table
// would put marketing claims in front of every translator working on button
// labels — and would make both harder to reason about.
//
// Kept in its own file rather than inside `screenshot_test.dart` so the board
// tests (`store_board_test.dart`) can read it without dragging in the whole app
// bootstrap that the screenshot suite needs.
import 'package:bike_control/widgets/ui/colors.dart';
import 'package:flutter/material.dart' show Color, HSLColor;

/// The scenes that make up the store listing, in the order they are shown in.
///
/// This IS the listing order — `scripts/prepare_store_screenshots.sh` numbers
/// the uploaded files `01_…`, `02_…` from the same sequence, and
/// `store_board_test.dart` asserts the two never drift. The hue ramp below
/// reads a scene's position out of this list, so it cannot disagree with the
/// order a shopper actually scrolls the boards in.
const List<String> kSceneOrder = <String>[
  'device',
  'trainer',
  'virtualshifting',
  'virtualshifting-settings',
  'customization',
  'companion',
];

/// The languages the boards are rendered in — one screenshot folder per
/// language, so the store listings get genuinely localized screenshots instead
/// of the English ones copied to every locale.
const List<String> kScreenshotLocales = <String>['en', 'de', 'es', 'fr', 'it', 'pl'];

/// The longest a headline may be before it stops fitting the board.
///
/// Measured against the narrowest board slot rather than guessed: the iPhone
/// canvas is 414 logical units wide, the headline strip is 86% of that, and the
/// type is `CustomFrame.titleFraction` of the width — which holds roughly 24
/// characters a line and three lines in the band. 56 leaves a line of headroom
/// for a translation that runs long.
///
/// Higher than the 52 the same board uses in BikeOtter, because that board
/// spends a fifth of its width on a per-scene mascot and this one has no art
/// column: the headline gets the whole strip.
///
/// `store_board_test.dart` enforces it, because the failure is invisible until
/// someone opens all 216 PNGs.
const int kSceneHeadlineMaxChars = 56;

/// The accent one phrase of every headline is painted in.
///
/// A light cyan out of the brand's own family (the gradient runs #0E74B7 →
/// #0E9297), lighter than both stops so it reads as emphasis on the darker end
/// of the board rather than as a second brand colour.
const Color kStoreAccentColor = Color(0xFF7DE3FF);

/// How far apart the two ends of the hue ramp sit, in degrees.
///
/// Scrolled past, six identical blue boards read as one image repeated; six
/// unrelated colours read as six apps. 24° is the middle: every board stays
/// recognisably this blue and the set still moves while you scroll it.
const double _hueSpread = 24;

/// Brand colours for the marketing board.
class StoreFrameStyle {
  const StoreFrameStyle({
    required this.gradientTop,
    required this.gradientBottom,
    this.titleColor = const Color(0xFFFFFFFF),
    this.accentColor = kStoreAccentColor,
  });

  final Color gradientTop;
  final Color gradientBottom;
  final Color titleColor;

  /// The colour one phrase of each headline is painted in.
  final Color accentColor;

  /// This style, rotated along the listing so the boards read as a series.
  ///
  /// The position comes from the scene's index in [kSceneOrder]; a scene that
  /// is not in it (the frameless website/blog shots, which carry no board at
  /// all) gets the unshifted style rather than an exception — the ramp is
  /// decoration.
  ///
  /// Only the two gradient stops move. The headline and its accent stay put:
  /// rotating those too would make the type a different colour on every board,
  /// which is the opposite of what a ramp is for.
  StoreFrameStyle forScene(String sceneId) {
    final order = kSceneOrder.indexOf(sceneId);
    if (order < 0) return this;
    final t = kSceneOrder.length == 1 ? 0.0 : order / (kSceneOrder.length - 1);
    final degrees = -_hueSpread / 2 + t * _hueSpread;
    return StoreFrameStyle(
      gradientTop: _rotateHue(gradientTop, degrees),
      gradientBottom: _rotateHue(gradientBottom, degrees),
      titleColor: titleColor,
      accentColor: accentColor,
    );
  }
}

/// The unshifted brand board: the app's own gradient pair, corner to corner.
const StoreFrameStyle kStoreBrandStyle = StoreFrameStyle(
  gradientTop: BKColor.main,
  gradientBottom: BKColor.mainEnd,
);

Color _rotateHue(Color c, double degrees) {
  final hsl = HSLColor.fromColor(c);
  return hsl.withHue((hsl.hue + degrees) % 360).toColor();
}

/// Scene id -> language code -> headline. English is the source of truth.
const Map<String, Map<String, String>> kSceneHeadlines = <String, Map<String, String>>{
  'device': <String, String>{
    'en': 'Control any trainer with ANY controller',
    'de': 'Steuere jeden Trainer mit JEDEM Controller',
    'es': 'Controla cualquier rodillo con CUALQUIER mando',
    // Shortened from "Contrôlez n'importe quel home-trainer avec N'IMPORTE
    // QUEL contrôleur" (68 characters), which ran past
    // [kSceneHeadlineMaxChars] and shrank the whole French board's type to
    // make room for a fourth line.
    'fr': 'Contrôlez tout home-trainer avec TOUT contrôleur',
    'it': 'Controlla qualsiasi rullo con QUALSIASI controller',
    'pl': 'Steruj każdym trenażerem DOWOLNYM kontrolerem',
  },
  'trainer': <String, String>{
    'en': 'Connect BikeControl to your trainer',
    'de': 'Verbinde BikeControl mit deinem Trainer',
    'es': 'Conecta BikeControl a tu rodillo',
    'fr': 'Connectez BikeControl à votre home-trainer',
    'it': 'Collega BikeControl al tuo rullo',
    'pl': 'Połącz BikeControl ze swoim trenażerem',
  },
  'customization': <String, String>{
    'en': 'Customize every controller button',
    'de': 'Passe jede Controller-Taste an',
    'es': 'Personaliza cada botón del mando',
    'fr': 'Personnalisez chaque bouton du contrôleur',
    'it': 'Personalizza ogni pulsante del controller',
    'pl': 'Dostosuj każdy przycisk kontrolera',
  },
  'companion': <String, String>{
    'en': 'Companion App mode with custom hotkeys',
    'de': 'Companion-App-Modus mit eigenen Tastenkürzeln',
    'es': 'Modo app complementaria con atajos personalizados',
    // Shortened from "Mode application compagnon avec raccourcis
    // personnalisés" (56); "mode compagnon" is what the feature is called in
    // French anyway.
    'fr': 'Mode compagnon avec raccourcis personnalisés',
    'it': 'Modalità app companion con scorciatoie personalizzate',
    'pl': 'Tryb aplikacji towarzyszącej z własnymi skrótami',
  },
  'virtualshifting': <String, String>{
    'en': 'Add or adjust Virtual Shifting functionality',
    'de': 'Virtuelles Schalten hinzufügen oder anpassen',
    'es': 'Añade o ajusta el cambio virtual',
    'fr': 'Ajoutez ou réglez le passage de vitesses virtuel',
    'it': 'Aggiungi o regola il cambio virtuale',
    'pl': 'Dodaj lub dostosuj wirtualną zmianę biegów',
  },
  'virtualshifting-settings': <String, String>{
    'en': 'Full Control of Virtual Shifting',
    'de': 'Volle Kontrolle über das virtuelle Schalten',
    'es': 'Control total del cambio virtual',
    'fr': 'Contrôle total du passage de vitesses virtuel',
    'it': 'Controllo totale del cambio virtuale',
    'pl': 'Pełna kontrola nad wirtualną zmianą biegów',
  },
};

/// Scene id -> language code -> the run of the headline painted in
/// [StoreFrameStyle.accentColor].
///
/// Always the SUBJECT of the claim — the thing a rider scanning the listing is
/// looking for — never the verb: "with **ANY controller**", "**custom
/// hotkeys**", "**Virtual Shifting**". A headline whose whole point is the
/// qualifier accents that instead ("**Full Control** of Virtual Shifting").
///
/// Per language, because these are substrings of the *translated* headline and
/// German does not put its noun where English does. A phrase that is off by one
/// character does not throw and does not warn — it silently renders that one
/// headline plain, which is the kind of miss nobody notices until the listing
/// is live. `store_board_test.dart` checks all 36.
const Map<String, Map<String, String>> kSceneAccents = <String, Map<String, String>>{
  'device': <String, String>{
    'en': 'ANY controller',
    'de': 'JEDEM Controller',
    'es': 'CUALQUIER mando',
    'fr': 'TOUT contrôleur',
    'it': 'QUALSIASI controller',
    'pl': 'DOWOLNYM kontrolerem',
  },
  'trainer': <String, String>{
    'en': 'your trainer',
    'de': 'deinem Trainer',
    'es': 'tu rodillo',
    'fr': 'votre home-trainer',
    'it': 'tuo rullo',
    'pl': 'swoim trenażerem',
  },
  'customization': <String, String>{
    'en': 'controller button',
    'de': 'Controller-Taste',
    'es': 'botón del mando',
    'fr': 'bouton du contrôleur',
    'it': 'pulsante del controller',
    'pl': 'przycisk kontrolera',
  },
  'companion': <String, String>{
    'en': 'custom hotkeys',
    'de': 'eigenen Tastenkürzeln',
    'es': 'atajos personalizados',
    'fr': 'raccourcis personnalisés',
    'it': 'scorciatoie personalizzate',
    'pl': 'własnymi skrótami',
  },
  'virtualshifting': <String, String>{
    'en': 'Virtual Shifting',
    'de': 'Virtuelles Schalten',
    'es': 'cambio virtual',
    'fr': 'passage de vitesses virtuel',
    'it': 'cambio virtuale',
    'pl': 'wirtualną zmianę biegów',
  },
  'virtualshifting-settings': <String, String>{
    'en': 'Full Control',
    'de': 'Volle Kontrolle',
    'es': 'Control total',
    'fr': 'Contrôle total',
    'it': 'Controllo totale',
    'pl': 'Pełna kontrola',
  },
};

/// The headline for a scene in a language, falling back to English.
///
/// Throws for an unknown scene rather than returning a placeholder: a missing
/// headline means the scene list and this table have drifted, and a board
/// captured with an empty headline looks deliberate.
String sceneHeadline(String sceneId, String language) {
  final byLanguage = kSceneHeadlines[sceneId];
  if (byLanguage == null) {
    throw ArgumentError('no headlines for scene `$sceneId` — add it to kSceneHeadlines');
  }
  return byLanguage[language] ?? byLanguage['en']!;
}

/// The accented run of a scene's headline in a language, falling back to
/// English and then to none.
///
/// Unlike [sceneHeadline] this does not throw for an unknown scene: the accent
/// is a decoration on a claim, not the claim, and a board is still a correct
/// board without it.
String? sceneAccent(String sceneId, String language) {
  final byLanguage = kSceneAccents[sceneId];
  if (byLanguage == null) return null;
  return byLanguage[language] ?? byLanguage['en'];
}
