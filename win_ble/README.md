# WinBle

[![win_ble version](https://img.shields.io/pub/v/win_ble?label=win_ble)](https://pub.dev/packages/win_ble)

Use the WinBle plugin to enable Bluetooth Low Energy in Flutter Windows and pure Dart projects (Windows only)

## Usage

First initialize WinBle, to initialize on Flutter Windows, get server path using `await WinServer.path`, and for pure dart projects ( Windows only ) Download [BleServer.exe](https://github.com/rohitsangwan01/win_ble/blob/main/lib/assets/BLEServer.exe) file and place in the same folder, checkout `example_dart` for more details

```dart
  // To initialize on Flutter Windows
  await WinBle.initialize(serverPath: await WinServer.path());

  // For pure dart projects
  await WinBle.initialize(serverPath: "Path of BLEServer.exe file");
```

Dispose WinBle after using

```dart
 WinBle.dispose();
```

To Start Scan

```dart
 WinBle.startScanning();

 StreamSubscription? scanStream = WinBle.scanStream.listen((event) {
  // Get Devices Here
 });
```

To Stop Scan

```dart
  WinBle.stopScanning();

  scanStream?.cancel();
```

To Connect

```dart
 // To Connect
 await WinBle.connect(address);

 // Get Connection Updates Here
 StreamSubscription  _connectionStream =
    WinBle.connectionStreamOf(device.address).listen((event) {
    // event will be a boolean , in which
    // true => Connected
    // false => Disconnected
 });
```

To Disconnect

```dart
  await WinBle.disconnect(address);
```

To get MaxMtuSize

```dart
  await WinBle.getMaxMtuSize(address);
```

Handle Bluetooth radio

```dart
  // To get rdaio status
  WinBle.getBluetoothState();

  // To get updates of radio state
  WinBle.bleState.listen((BleState state) {
    // Get BleState (On, Off, Unknown, Disabled, Unsupported)
  });

  // To turn on radio
  WinBle.updateBluetoothState(true);

  // To turn off radio
  WinBle.updateBluetoothState(false);
```

Pairing Options

```dart
  // To Pair
  await WinBle.pair(address);

  // To UnPair
  await WinBle.unPair(address);

  // To Check if Device can be Paired
  bool canPair = await WinBle.canPair(address);

  // To Check if Device is Already Paired
  bool isPaired = await WinBle.isPaired(address);
```

Rest All Methods are

```dart
  // To Get Services
  var services = await WinBle.discoverServices(address);

  // To Get Characteristic
  List<BleCharacteristic> bleCharacteristics = await WinBle.discoverCharacteristics(address: address, serviceId: serviceID);

  // To Read Characteristic
  List<int> data = await WinBle.read(address: address, serviceId: serviceID, characteristicId: charID);

  // To Write Characteristic
  await WinBle.write( address: address, service: serviceID,  characteristic: charID,  data: data, writeWithResponse: writeWithResponse);

  // To Start Subscription
  await WinBle.subscribeToCharacteristic(address: address, serviceId: serviceID, characteristicId: charID);

  // To Stop Subscription
  await WinBle.unSubscribeFromCharacteristic(address: address, serviceId: serviceID, characteristicId: charID);

  // Get Characteristic Value Updates Here
   StreamSubscription _characteristicValueStream = WinBle.characteristicValueStream.listen((event) {
     // Here We will Receive All Characteristic Events
   });

```

## Note

Requires Windows version >= 10.0.15014

<details>
  <summary>If windows release build opens cmd while running app, try this</summary>
  
Edit your `/windows/runner/main.cpp` file, this is a known flutter [issue](https://github.com/flutter/flutter/issues/47891)

```c++
if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()){
CreateAndAttachConsole();
}
// Add this Code
// <------- From Here --------- >
else{
    STARTUPINFO si = {0};
    si.cb = sizeof(si);
    si.dwFlags = STARTF_USESHOWWINDOW;
    si.wShowWindow = SW_HIDE;

    PROCESS_INFORMATION pi = {0};
    WCHAR lpszCmd[MAX_PATH] = L"cmd.exe";
    if (::CreateProcess(NULL, lpszCmd, NULL, NULL, FALSE, CREATE_NEW_CONSOLE | CREATE_NO_WINDOW, NULL, NULL, &si, &pi))
    {
      do
      {
        if (::AttachConsole(pi.dwProcessId))
        {
          ::TerminateProcess(pi.hProcess, 0);
          break;
        }
      } while (ERROR_INVALID_HANDLE == GetLastError());
      ::CloseHandle(pi.hProcess);
      ::CloseHandle(pi.hThread);
    }
}
// <------- UpTo Here --------- >
```

</details>

## Additional information

Thanks to [noble-winrt](https://github.com/urish/noble-winrt) for initial BleServer Code

This is Just The Initial Version feel free to Contribute or Report any Bug!
