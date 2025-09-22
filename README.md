# SwiftControl

<img src="logo.jpg" alt="SwiftControl Logo"/>

## Description

With SwiftControl you can **control your favorite trainer app** using your Zwift Click, Zwift Ride or Zwift Play devices. Here's what you can do with it, depending on your configuration:
- Virtual Gear shifting
- Steering / turning
- adjust workout intensity
- control music on your device
- more? If you can do it via keyboard, mouse or touch, you can do it with SwiftControl


https://github.com/user-attachments/assets/1f81b674-1628-4763-ad66-5f3ed7a3f159




## Downloads
Get the latest version here: https://github.com/jonasbark/swiftcontrol/releases

## Supported Apps
- MyWhoosh
- indieVelo / Training Peaks
- Biketerra.com
- any other: 
  - Android: you can customize simulated touch points of all your buttons in the app
  - Desktop: you can customize keyboard shortcuts and mouse clicks in the app

## Supported Devices
- Zwift Click
- Zwift Click v2
- Zwift Ride
- Zwift Play

## Supported Platforms
- Android
  - App is losing connection over time? Read about how to [keep the app alive](https://dontkillmyapp.com/).
- macOS
- Windows 
  - Windows may flag the app as virus. I think it does so because the app does control the mouse and keyboard.
  - Bluetooth connection unstable? You may need to use an [external Bluetooth adapter](https://github.com/jonasbark/swiftcontrol/issues/14#issuecomment-3193839509).
  - Make sure your Zwift device is not paired with Windows Bluetooth settings: [more information](https://github.com/jonasbark/swiftcontrol/issues/70).
- [Web](https://jonasbark.github.io/swiftcontrol/) (you won't be able to do much)
- NOT SUPPORTED: iOS (iPhone, iPad) as Apple does not provide any way to simulate touches or keyboard events

## Troubleshooting
- Your Zwift device is found but connection does not work properly? You may need to update the firmware in Zwift Companion app.

## How does it work?
The app connects to your Zwift device automatically. It does not connect to your trainer itself.

- When using Android a touch on a certain part of the screen is simulated to trigger the action.
- When using macOS or Windows a keyboard or mouse click is used to trigger the action. 
  - there are predefined Keymaps for MyWhoosh, indieVelo / Training Peaks, and others
  - you can also create your own Keymaps for any other app
  - you can also use the mouse to click on a certain part of the screen, or use keyboard shortcuts

## Alternatives
- [qdomyos-zwift](https://www.qzfitness.com/) directly controls the trainer (as opposed to controlling the trainer app)

## Donate
Please consider donating to support the development of this app :)

[![Donate](https://img.shields.io/badge/Donate-PayPal-green.svg)](https://paypal.me/boni)

## Development

For information about setting up automated Play Store deployment, see [docs/PLAY_STORE_DEPLOYMENT.md](docs/PLAY_STORE_DEPLOYMENT.md).

