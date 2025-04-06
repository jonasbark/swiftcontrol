import 'dart:async';
import 'dart:io';

import 'package:dartx/dartx.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:swift_control/main.dart';
import 'package:window_manager/window_manager.dart';

import '../bluetooth/messages/click_notification.dart';
import '../bluetooth/messages/notification.dart';
import '../bluetooth/messages/play_notification.dart';
import '../bluetooth/messages/ride_notification.dart';
import '../utils/keymap/apps/custom_app.dart';
import '../utils/keymap/buttons.dart';
import '../utils/keymap/keymap.dart';
import '../widgets/custom_keymap_selector.dart';

final touchAreaSize = 42.0;

class TouchAreaSetupPage extends StatefulWidget {
  const TouchAreaSetupPage({super.key});

  @override
  State<TouchAreaSetupPage> createState() => _TouchAreaSetupPageState();
}

class _TouchAreaSetupPageState extends State<TouchAreaSetupPage> {
  File? _backgroundImage;
  late StreamSubscription<BaseNotification> _actionSubscription;
  ZwiftButton? _pressedButton;

  Future<void> _pickScreenshot() async {
    final picker = ImagePicker();
    final result = await picker.pickImage(source: ImageSource.gallery);
    if (result != null) {
      setState(() {
        _backgroundImage = File(result.path);
      });
    }
  }

  void _saveAndClose() {
    Navigator.of(context).pop(true);
  }

  @override
  void dispose() {
    super.dispose();
    _actionSubscription.cancel();
    // Exit full screen
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual, overlays: SystemUiOverlay.values);
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      windowManager.setFullScreen(false);
    }
  }

  @override
  void initState() {
    super.initState();

    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky, overlays: []);
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      windowManager.setFullScreen(true);
    }
    _actionSubscription = connection.actionStream.listen((data) {
      if (!mounted) {
        return;
      }
      if (data is ClickNotification) {
        _pressedButton = data.buttonsClicked.singleOrNull;
      }
      if (data is PlayNotification) {
        _pressedButton = data.buttonsClicked.singleOrNull;
      }
      if (data is RideNotification) {
        _pressedButton = data.buttonsClicked.singleOrNull;
      }

      if (_pressedButton != null) {
        if (actionHandler.supportedApp!.keymap.getKeyPair(_pressedButton!) == null) {
          actionHandler.supportedApp!.keymap.keyPairs.add(
            KeyPair(
              touchPosition: context.size!.center(Offset.zero),
              buttons: [_pressedButton!],
              physicalKey: null,
              logicalKey: null,
            ),
          );
          setState(() {});
        }
      }
    });
  }

  Widget _buildDraggableArea({
    required Offset position,
    required void Function(Offset newPosition) onPositionChanged,
    required Color color,
    required KeyPair keyPair,
    required String label,
  }) {
    return Positioned(
      left: position.dx,
      top: position.dy,
      child: PopupMenuButton<PhysicalKeyboardKey>(
        tooltip: 'Drag or click for special keys',
        itemBuilder:
            (context) => [
              PopupMenuItem<PhysicalKeyboardKey>(
                value: null,
                child: const Text('Set Keyboard shortcut'),
                onTap: () async {
                  await showDialog<void>(
                    context: context,
                    builder:
                        (c) =>
                            HotKeyListenerDialog(customApp: actionHandler.supportedApp! as CustomApp, keyPair: keyPair),
                  );
                  setState(() {});
                },
              ),
              if (keyPair.physicalKey != null)
                PopupMenuItem<PhysicalKeyboardKey>(
                  value: null,
                  child: const Text('Use as touch button'),
                  onTap: () {
                    keyPair.physicalKey = null;
                    keyPair.logicalKey = null;
                    setState(() {});
                  },
                ),
            ],
        onSelected: (key) {
          keyPair.physicalKey = key;
          keyPair.logicalKey = null;
          setState(() {});
        },
        child: Container(
          color: kDebugMode && false ? Colors.yellow : null,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Draggable(
                feedback: Material(
                  color: Colors.transparent,
                  child: _TouchDot(color: Colors.yellow, label: label, keyPair: keyPair),
                ),
                onDragUpdate: (details) {
                  print('Dragging: ${details.localPosition}');
                },
                childWhenDragging: const SizedBox.shrink(),
                onDraggableCanceled: (_, offset) {
                  print('Drag canceled: ${offset}');
                  setState(() => onPositionChanged(offset));
                },
                child: _TouchDot(color: color, label: label, keyPair: keyPair),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = Platform.isWindows || Platform.isLinux || Platform.isMacOS;
    final devicePixelRatio = isDesktop ? 1.0 : MediaQuery.devicePixelRatioOf(context);
    return Scaffold(
      body: Stack(
        children: [
          if (_backgroundImage != null)
            Positioned.fill(child: Opacity(opacity: 0.5, child: Image.file(_backgroundImage!, fit: BoxFit.contain)))
          else
            Center(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  spacing: 8,
                  children: [
                    Text('''1. Create an in-game screenshot of your app (e.g. within MyWhoosh)
2. Load the screenshot with the button below
3. Make sure the app is in the correct orientation (portrait or landscape)
4. Press a button on your Zwift device to create a touch area
5. Drag the touch areas to the desired position on the screenshot
5. Save and close this screen'''),
                    ElevatedButton(
                      onPressed: () {
                        _pickScreenshot();
                      },
                      child: Text('Load in-game screenshot for placement'),
                    ),
                  ],
                ),
              ),
            ),
          // Touch Areas
          ...?actionHandler.supportedApp?.keymap.keyPairs.map(
            (keyPair) => _buildDraggableArea(
              position: Offset(
                keyPair.touchPosition.dx / devicePixelRatio - touchAreaSize / 2,
                keyPair.touchPosition.dy / devicePixelRatio - touchAreaSize / 2 - (isDesktop ? touchAreaSize * 1.5 : 0),
              ),
              keyPair: keyPair,
              onPositionChanged: (newPos) {
                final converted =
                    newPos.translate(touchAreaSize / 2, touchAreaSize / 2 + (isDesktop ? touchAreaSize * 1.5 : 0)) *
                    devicePixelRatio;
                keyPair.touchPosition = converted;
                setState(() {});
              },
              color: Colors.red,
              label: keyPair.buttons.joinToString(transform: (e) => e.name, separator: '\n'),
            ),
          ),

          Positioned(
            top: 40,
            right: 20,
            child: Row(
              spacing: 8,
              children: [
                ElevatedButton.icon(
                  onPressed: () {
                    actionHandler.supportedApp?.keymap.reset();
                    setState(() {});
                  },
                  icon: const Icon(Icons.lock_reset),
                  label: Text('Reset'),
                ),
                ElevatedButton.icon(onPressed: _saveAndClose, icon: const Icon(Icons.save), label: const Text("Save")),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TouchDot extends StatelessWidget {
  final Color color;
  final String label;
  final KeyPair keyPair;

  const _TouchDot({required this.color, required this.label, required this.keyPair});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: touchAreaSize,
          height: touchAreaSize,
          decoration: BoxDecoration(
            color: color.withOpacity(0.6),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.black, width: 2),
          ),
          child: Icon(
            keyPair.isSpecialKey
                ? Icons.music_note_outlined
                : keyPair.physicalKey != null
                ? Icons.keyboard_alt_outlined
                : Icons.add,
          ),
        ),

        Text(label, style: TextStyle(color: Colors.black, fontSize: 12)),
        if (keyPair.physicalKey != null)
          Text(switch (keyPair.physicalKey) {
            PhysicalKeyboardKey.mediaPlayPause => 'Media: Play/Pause',
            PhysicalKeyboardKey.mediaStop => 'Media: Stop',
            PhysicalKeyboardKey.mediaTrackPrevious => 'Media: Previous',
            PhysicalKeyboardKey.mediaTrackNext => 'Media: Next',
            PhysicalKeyboardKey.audioVolumeUp => 'Media: Volume Up',
            PhysicalKeyboardKey.audioVolumeDown => 'Media: Volume Down',
            _ => keyPair.logicalKey?.keyLabel ?? 'Unknown',
          }, style: TextStyle(color: Colors.grey, fontSize: 12)),
      ],
    );
  }
}
