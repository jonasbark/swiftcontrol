# media_key_detector_windows

[![style: very good analysis][very_good_analysis_badge]][very_good_analysis_link]

The windows implementation of `media_key_detector`.

## Features

This plugin provides global media key detection on Windows using two complementary Windows APIs:

1. **RegisterHotKey API** - Captures system-wide media key events
2. **Raw Input API** - Captures keyboard HID events from devices like Bluetooth media remotes

This dual approach ensures that media keys are detected from all sources, including Bluetooth remote controllers that appear as keyboard devices.

### Supported Media Keys

- Play/Pause (VK_MEDIA_PLAY_PAUSE)
- Next Track (VK_MEDIA_NEXT_TRACK)
- Previous Track (VK_MEDIA_PREV_TRACK)
- Volume Up (VK_VOLUME_UP)
- Volume Down (VK_VOLUME_DOWN)

### Implementation Details

The plugin uses:
- `RegisterHotKey` Windows API for global hotkey registration (captures system media keys)
- `Raw Input API` for capturing keyboard HID events from Bluetooth remotes and other HID devices
- Event channels for communicating media key events to Dart
- Window message handlers to process WM_HOTKEY and WM_INPUT messages

Both hotkeys and raw input are registered when `setIsPlaying(true)` is called and automatically unregistered when `setIsPlaying(false)` is called or when the plugin is destroyed.

### Bluetooth Remote Support

The plugin now supports Bluetooth media remotes that pair as keyboard devices. These devices send keyboard HID events instead of media key events, which are captured via the Raw Input API. This includes:

- Car/bike media remote controllers
- Bluetooth media buttons
- Other HID devices that send volume and media control keys

## Usage

This package is [endorsed][endorsed_link], which means you can simply use `media_key_detector`
normally. This package will be automatically included in your app when you do.

```dart
import 'package:media_key_detector/media_key_detector.dart';

// Enable media key detection
mediaKeyDetector.setIsPlaying(isPlaying: true);

// Listen for media key events
mediaKeyDetector.addListener((MediaKey key) {
  switch (key) {
    case MediaKey.playPause:
      // Handle play/pause
      break;
    case MediaKey.fastForward:
      // Handle next track
      break;
    case MediaKey.rewind:
      // Handle previous track
      break;
    case MediaKey.volumeUp:
      // Handle volume up
      break;
    case MediaKey.volumeDown:
      // Handle volume down
      break;
  }
});
```

[endorsed_link]: https://flutter.dev/docs/development/packages-and-plugins/developing-packages#endorsed-federated-plugin
[very_good_analysis_badge]: https://img.shields.io/badge/style-very_good_analysis-B22C89.svg
[very_good_analysis_link]: https://pub.dev/packages/very_good_analysis
