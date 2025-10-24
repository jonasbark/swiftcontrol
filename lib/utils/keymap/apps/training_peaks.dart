import 'package:dartx/dartx.dart';
import 'package:flutter/services.dart';
import 'package:swift_control/utils/keymap/apps/supported_app.dart';
import 'package:swift_control/utils/keymap/buttons.dart';

import '../keymap.dart';

class TrainingPeaks extends SupportedApp {
  TrainingPeaks()
    : super(
        name: 'TrainingPeaks Virtual / IndieVelo',
        packageName: "com.indieVelo.client",
        keymap: Keymap(
          keyPairs: [
            // Explicit controller-button mappings with updated touch coordinates
            KeyPair(
              buttons: [ControllerButton.shiftUpRight],
              physicalKey: PhysicalKeyboardKey.numpadAdd,
              logicalKey: LogicalKeyboardKey.numpadAdd,
              touchPosition: Offset(22.65384615384622, 7.0769230769229665),
            ),
            KeyPair(
              buttons: [ControllerButton.shiftUpLeft],
              physicalKey: PhysicalKeyboardKey.numpadAdd,
              logicalKey: LogicalKeyboardKey.numpadAdd,
              touchPosition: Offset(18.14448747554958, 6.772862761010401),
            ),
            KeyPair(
              buttons: [ControllerButton.shiftDownLeft],
              physicalKey: PhysicalKeyboardKey.numpadSubtract,
              logicalKey: LogicalKeyboardKey.numpadSubtract,
              touchPosition: Offset(18.128205128205135, 6.75213675213675),
            ),
            KeyPair(
              buttons: [ControllerButton.shiftDownRight],
              physicalKey: PhysicalKeyboardKey.numpadSubtract,
              logicalKey: LogicalKeyboardKey.numpadSubtract,
              touchPosition: Offset(22.61769250748708, 8.13909075507417),
            ),

            // Navigation buttons (keep arrow key mappings and add touch positions)
            KeyPair(
              buttons: ControllerButton.values.filter((e) => e == ControllerButton.navigationRight).toList(),
              physicalKey: PhysicalKeyboardKey.arrowRight,
              logicalKey: LogicalKeyboardKey.arrowRight,
              touchPosition: Offset(56.75858807279006, 92.42753954973301),
            ),
            KeyPair(
              buttons: ControllerButton.values.filter((e) => e == ControllerButton.navigationLeft).toList(),
              physicalKey: PhysicalKeyboardKey.arrowLeft,
              logicalKey: LogicalKeyboardKey.arrowLeft,
              touchPosition: Offset(41.11538461538456, 92.64957264957286),
            ),
            KeyPair(
              buttons: [ControllerButton.navigationUp],
              physicalKey: PhysicalKeyboardKey.arrowUp,
              logicalKey: LogicalKeyboardKey.arrowUp,
              touchPosition: Offset(42.28406293368177, 92.61854987939971),
            ),

            // Face buttons with touch positions and keyboard fallbacks where sensible
            KeyPair(
              buttons: [ControllerButton.z],
              physicalKey: null,
              logicalKey: null,
              touchPosition: Offset(33.993890038715456, 92.43667306401531),
            ),
            KeyPair(
              buttons: [ControllerButton.a],
              physicalKey: null,
              logicalKey: null,
              touchPosition: Offset(47.37191097597044, 92.86963594239016),
            ),
            KeyPair(
              buttons: [ControllerButton.b],
              physicalKey: null,
              logicalKey: null,
              touchPosition: Offset(41.12364102683652, 83.72743323236598),
            ),
            KeyPair(
              buttons: [ControllerButton.y],
              physicalKey: null,
              logicalKey: null,
              touchPosition: Offset(58.52936866684111, 84.31131200977018),
            ),

            // Keep other existing mappings (toggle UI, increase/decrease resistance)
            KeyPair(
              buttons: ControllerButton.values.filter((e) => e.action == InGameAction.toggleUi).toList(),
              physicalKey: PhysicalKeyboardKey.keyH,
              logicalKey: LogicalKeyboardKey.keyH,
            ),
            KeyPair(
              buttons: ControllerButton.values.filter((e) => e.action == InGameAction.increaseResistance).toList(),
              physicalKey: PhysicalKeyboardKey.pageUp,
              logicalKey: LogicalKeyboardKey.pageUp,
            ),
            KeyPair(
              buttons: ControllerButton.values.filter((e) => e.action == InGameAction.decreaseResistance).toList(),
              physicalKey: PhysicalKeyboardKey.pageDown,
              logicalKey: LogicalKeyboardKey.pageDown,
            ),
          ],
        ),
      );
}
