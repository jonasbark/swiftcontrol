// ignore_for_file: avoid_print, prefer_final_fields, constant_identifier_names

import 'dart:async';
import 'dart:typed_data';

import 'package:win_ble/src/models/ble_state.dart';
import 'package:win_ble/src/utils/win_connector.dart';
import 'package:win_ble/src/utils/win_helper.dart';

import 'models/ble_characteristic.dart';
import 'models/ble_device.dart';

class WinBle {
  static String _previousBleState = "";
  static bool _isInitialized = false;
  static final WinConnector _channel = WinConnector();

  /// [Stream Controllers]
  static StreamController<BleDevice> _scanStreamController =
      StreamController.broadcast();
  static StreamController<Map<String, dynamic>> _connectionStreamController =
      StreamController.broadcast();
  static StreamController _characteristicValueStreamController =
      StreamController.broadcast();
  static StreamController<BleState> _bleStateStreamController =
      StreamController.broadcast();

  /// make sure to [initialize] WinBle once before using it
  /// call [dispose] when Done
  static Future<void> initialize({
    required String serverPath,
    bool enableLog = false,
  }) async {
    if (_isInitialized) throw "WinBle is already initialized";
    try {
      WinHelper.showLog = enableLog;
      await _channel.initialize(
        onData: _handleMessages,
        serverPath: serverPath,
      );
      _isInitialized = true;
    } catch (e) {
      dispose();
      throw e.toString();
    }
  }

  /// call [dispose] method to close all resources
  static void dispose() {
    _isInitialized = false;
    _channel.dispose();
  }

  static void _handleMessages(message) {
    WinHelper.printLog("Received Message : $message");
    switch (message["_type"]) {
      /// ScanResult events
      case "scanResult":
        _scanStreamController.add(BleDevice.fromJson(message));
        break;

      /// Ble state updates
      case "ble_state":
        String state = message["state"];
        if (state == _previousBleState) return;
        _previousBleState = state;
        _bleStateStreamController.add(BleState.parse(state));
        break;

      /// Handle Disconnection events
      case "disconnectEvent":
        String device = message["device"];
        _connectionStreamController.add({
          "device": WinHelper.getAddressFromDevice(device) ?? device,
          "connected": false,
        });
        break;

      /// Handle characteristic value updates
      case "valueChangedNotification":
        String subscriptionKey = message["subscriptionId"]?.toString() ?? "";
        Map<String, String>? data =
            WinHelper.getDataFromSubscriptionKey(subscriptionKey);
        if (data != null) {
          var value = message["value"];
          var result = {};
          result.addAll(data);
          result.addAll({"value": value});
          _characteristicValueStreamController.add(result);
        } else {
          WinHelper.printLog(
              "Received Unknown Data from SubscriptionKey : $subscriptionKey");
        }
        break;
    }
  }

  /// To get ble server version
  static Future<String> version() async {
    try {
      return await _channel.invokeMethod("version");
    } catch (e) {
      return 'Unknown';
    }
  }

  /// To get ble radio state
  static Future<BleState> getBluetoothState() async {
    try {
      var state = await _channel.invokeMethod("radioState");
      return BleState.parse(state);
    } catch (e) {
      return BleState.Unknown;
    }
  }

  /// To turn on/off ble radio
  static Future<BleState> updateBluetoothState(bool turnOn) async {
    try {
      var state = await _channel.invokeMethod("changeRadioState", args: {
        "turnOn": turnOn,
      });
      return BleState.parse(state);
    } catch (e) {
      return BleState.Unknown;
    }
  }

  /// To get max MtuSize
  static Future getMaxMtuSize(String address) async {
    var size = await _channel.invokeMethod("getMaxMtuSize", args: {
      "device": WinHelper.getDeviceFromAddress(address),
    });
    return size;
  }

  /// To [Start Scanning ]
  static void startScanning() {
    _channel.invokeMethod("scan", waitForResult: false);
  }

  /// To [Stop Scanning]
  static void stopScanning() {
    _channel.invokeMethod("stopScan", waitForResult: false);
  }

  /// [connect] will update a Stream of boolean [getConnectionStream]
  /// true if connected
  /// false if disconnected
  static Future<void> connect(String address) async {
    try {
      var result = await _channel.invokeMethod("connect", args: {
        "address": address.replaceAll(":", ""),
      });
      WinHelper.deviceMap[address] = result;
      // we have to perform an operation on device in order to make a connection
      var services = await discoverServices(address, forceRefresh: true);
      // A temporary way of detecting connection : if services are empty then connection is failed
      bool connectionFailed = services.isEmpty;
      _connectionStreamController.add({
        "device": address,
        "connected": !connectionFailed,
      });
    } catch (e) {
      rethrow;
    }
  }

  /// [disconnect] will update a Stream of boolean [getConnectionStream]
  /// and also ignore if that device is already disconnected
  static Future<void> disconnect(address) async {
    try {
      await _channel.invokeMethod("disconnect", args: {
        "device": WinHelper.getDeviceFromAddress(address),
      });
      _connectionStreamController.add({
        "device": address,
        "connected": false,
      });
      WinHelper.deviceMap[address] = null;
    } catch (e) {
      if (e.toString().contains("not found")) {
        // ignore for now
      } else {
        rethrow;
      }
    }
  }

  /// [canPair] will return a boolean
  static Future<bool> canPair(String address) async {
    try {
      var result = await _channel.invokeMethod("canPair", args: {
        "device": WinHelper.getDeviceFromAddress(address),
      });
      return result != null && result;
    } catch (e) {
      rethrow;
    }
  }

  /// [isPaired] will return a boolean
  /// [forceRefresh] will get the latest pair status of this device
  static Future<bool> isPaired(
    String address, {
    bool forceRefresh = false,
  }) async {
    try {
      var result = await _channel.invokeMethod("isPaired", args: {
        "device": forceRefresh
            ? address.replaceAll(":", "")
            : WinHelper.getDeviceFromAddress(address),
        "forceRefresh": forceRefresh,
      });
      return result != null && result;
    } catch (e) {
      rethrow;
    }
  }

  /// [pair] will send a pairing command
  /// it will be completed on Successful Pairing
  /// or it will throw Error on Unsuccessful Pairing
  static Future<void> pair(String address) async {
    try {
      var result = await _channel.invokeMethod("pair", args: {
        "device": WinHelper.getDeviceFromAddress(address),
      });
      if (result == null || result != "Paired") {
        throw result;
      }
    } catch (e) {
      rethrow;
    }
  }

  /// [unPair] will try to Un-pair
  static Future<void> unPair(String address) async {
    try {
      var result = await _channel.invokeMethod("unPair", args: {
        "device": WinHelper.getDeviceFromAddress(address),
      });
      if (result == null || result != "Unpaired") {
        throw result;
      }
    } catch (e) {
      rethrow;
    }
  }

  /// [discoverServices] will return a list of services List
  static Future<List<String>> discoverServices(address,
      {bool forceRefresh = false}) async {
    List? services = await _channel.invokeMethod("services", args: {
      "device": WinHelper.getDeviceFromAddress(address),
      "forceRefresh": forceRefresh,
    });
    return services?.map((e) => WinHelper.fromWindowsUuid(e)).toList() ?? [];
  }

  /// [discoverCharacteristics] will return a list of [BleCharacteristic]
  static Future<List<BleCharacteristic>> discoverCharacteristics(
      {required String address,
      required String serviceId,
      bool forceRefresh = false}) async {
    var data = await _channel.invokeMethod("characteristics", args: {
      "device": WinHelper.getDeviceFromAddress(address),
      "service": WinHelper.toWindowsUuid(serviceId),
      "forceRefresh": forceRefresh,
    });
    return List<BleCharacteristic>.from(
        data.map((e) => BleCharacteristic.fromJson(e)));
  }

  /// [read] will read characteristic value and returns a List<int>
  static Future<List<int>> read(
      {required String address,
      required String serviceId,
      required String characteristicId}) async {
    var data = await _channel.invokeMethod("read", args: {
      "device": WinHelper.getDeviceFromAddress(address),
      "service": WinHelper.toWindowsUuid(serviceId),
      "characteristic": WinHelper.toWindowsUuid(characteristicId),
    });
    return List<int>.from(data);
  }

  /// [write] will write characteristic value and returns error if something is wrong
  /// wrap in try catch to capture error
  static Future<void> write(
      {required String address,
      required String service,
      required String characteristic,
      required Uint8List data,
      required bool writeWithResponse}) async {
    await _channel.invokeMethod("write", args: {
      "device": WinHelper.getDeviceFromAddress(address),
      "service": WinHelper.toWindowsUuid(service),
      "characteristic": WinHelper.toWindowsUuid(characteristic),
      "value": data,
      "writeWithResponse": writeWithResponse
    });
  }

  /// [subscribeToCharacteristic] will subscribe to characteristic and
  /// we can get update on [connectionStream]
  /// call [connectionStreamOf] to get value of specific characteristic
  static Future<void> subscribeToCharacteristic(
      {required String address,
      required String serviceId,
      required String characteristicId}) async {
    await _channel.invokeMethod("subscribe", args: {
      "device": WinHelper.getDeviceFromAddress(address),
      "service": WinHelper.toWindowsUuid(serviceId),
      "characteristic": WinHelper.toWindowsUuid(characteristicId),
    }).then((result) {
      WinHelper.subscriptions[result.toString()] = {
        "address": address,
        "serviceId": serviceId,
        "characteristicId": characteristicId
      };
    });
  }

  /// [unSubscribeFromCharacteristic] will unsubscribe from characteristic , throws error if this characteristic is not subscribed
  static Future<void> unSubscribeFromCharacteristic(
      {required String address,
      required String serviceId,
      required String characteristicId}) async {
    await _channel.invokeMethod("unsubscribe", args: {
      "device": WinHelper.getDeviceFromAddress(address),
      "service": WinHelper.toWindowsUuid(serviceId),
      "characteristic": WinHelper.toWindowsUuid(characteristicId),
    }).then((result) {
      WinHelper.subscriptions.remove(result.toString());
    });
  }

  /// All Streams
  ///
  /// use [scanStream] to get scan results
  static Stream<BleDevice> get scanStream => _scanStreamController.stream;

  /// we can get [connectionStream] to get update on connection
  static Stream<Map<String, dynamic>> get connectionStream =>
      _connectionStreamController.stream;

  /// [bleState] is a stream to get current Ble Status
  static Stream<BleState> get bleState => _bleStateStreamController.stream;

  /// [characteristicValueStream] is a stream to get characteristic value updates
  static Stream get characteristicValueStream =>
      _characteristicValueStreamController.stream;

  /// to get [connection update] for a specific device
  static Stream<bool> connectionStreamOf(String address) =>
      _connectionStreamController.stream
          .where((event) => event["device"] == address)
          .map((event) => event["connected"]);

  /// to get update of a [specific characteristic]
  static Stream characteristicValueStreamOf({
    required String address,
    required String serviceId,
    required String characteristicId,
  }) {
    return _characteristicValueStreamController.stream
        .where((event) =>
            event["address"] == address &&
            event["serviceId"] == serviceId &&
            event["characteristicId"] == characteristicId)
        .map((event) => event["value"]);
  }
}
