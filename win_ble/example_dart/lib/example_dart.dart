import 'package:win_ble/win_ble.dart';

void main() async {
  print("Initializing WinBle");

  // This is BleServerFile included in the package, please download and add that file to your project and change the path
  String serverPath = "..\\lib\\assets\\BLEServer.exe";

  await WinBle.initialize(enableLog: false, serverPath: serverPath);
  print("WinBle initialized");

  WinBle.bleState.listen((event) {
    print("Ble state: $event");
  });

  List<BleDevice> devices = [];
  WinBle.scanStream.listen((device) {
    if (devices.any((element) =>
        element.address == device.address && element.name == device.name)) {
      return;
    }
    devices.add(device);
    print(
      "Found device: ${device.name.isEmpty ? "Unknown" : device.name} - ${device.address}",
    );
  });

  // Start scanning
  WinBle.startScanning();

  // Stop scanning after 10 seconds
  await Future.delayed(Duration(seconds: 10));
  print("Stopping scan");

  WinBle.stopScanning();
  WinBle.dispose();
}
