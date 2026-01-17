# 0.0.3

- Add Raw Input API support for capturing keyboard HID events
- Enable detection of Bluetooth media remotes that appear as keyboard devices
- Add support for car/bike media remote controllers on Windows
- Improve compatibility with various HID devices sending media key events
- Dual-mode detection: RegisterHotKey for system media keys + Raw Input for HID devices

# 0.0.2

- Implement global media key detection using Windows RegisterHotKey API
- Add event channel support for media key events
- Media keys now work even when app is not focused
- Improved error handling for hotkey registration
- Added support for volume up and volume down hotkeys

# 0.0.1

- Initial Release
