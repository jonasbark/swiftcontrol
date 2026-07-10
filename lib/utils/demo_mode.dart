/// Video / demo overrides, all off by default and set via `--dart-define`.
///
/// Used to record clean, localized walkthrough videos of the app without the
/// recording machine's system locale or its Bluetooth-permission state getting
/// in the way (walkthroughs run against emulated devices, so the real
/// permission prompts are irrelevant noise).
///
/// Example:
///   flutter run --dart-define=DEMO_LOCALE=en --dart-define=DEMO_HIDE_PERMISSIONS=true
library;

/// Force the app UI locale (language code, e.g. `en`). Empty = follow the
/// system locale as usual.
const demoLocaleOverride = String.fromEnvironment('DEMO_LOCALE');

/// Hide the Bluetooth / permission requirements card on the start page.
const demoHidePermissions = bool.fromEnvironment('DEMO_HIDE_PERMISSIONS');
