import 'dart:async';
import 'dart:io';

import 'package:dartx/dartx.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:swift_control/main.dart';
import 'package:swift_control/utils/actions/android.dart';
import 'package:swift_control/utils/requirements/android.dart';
import 'package:universal_ble/universal_ble.dart';

import 'devices/base_device.dart';
import 'devices/zwift/constants.dart';
import 'messages/notification.dart';

class Connection {
  final devices = <BaseDevice>[];
  var _androidNotificationsSetup = false;

  final _connectionQueue = <BaseDevice>[];
  var _handlingConnectionQueue = false;

  final Map<BaseDevice, StreamSubscription<BaseNotification>> _streamSubscriptions = {};
  final StreamController<BaseNotification> _actionStreams = StreamController<BaseNotification>.broadcast();
  Stream<BaseNotification> get actionStream => _actionStreams.stream;

  final Map<BaseDevice, StreamSubscription<bool>> _connectionSubscriptions = {};
  final StreamController<BaseDevice> _connectionStreams = StreamController<BaseDevice>.broadcast();
  Stream<BaseDevice> get connectionStream => _connectionStreams.stream;

  final _lastScanResult = <BleDevice>[];
  final ValueNotifier<bool> hasDevices = ValueNotifier(false);
  final ValueNotifier<bool> isScanning = ValueNotifier(false);

  void initialize() {
    UniversalBle.onAvailabilityChange = (available) {
      _actionStreams.add(LogNotification('Bluetooth availability changed: $available'));
      if (available == AvailabilityState.poweredOn && !isScanning.value) {
        performScanning();
      } else if (available == AvailabilityState.poweredOff) {
        reset();
      }
    };
    UniversalBle.onScanResult = (result) {
      if (_lastScanResult.none((e) => e.deviceId == result.deviceId)) {
        _lastScanResult.add(result);
        final scanResult = BaseDevice.fromScanResult(result);

        if (scanResult != null) {
          _actionStreams.add(LogNotification('Found new device: ${scanResult.runtimeType}'));
          _addDevices([scanResult]);
        } else {
          final manufacturerData = result.manufacturerDataList;
          final data = manufacturerData
              .firstOrNullWhere((e) => e.companyId == ZwiftConstants.ZWIFT_MANUFACTURER_ID)
              ?.payload;
          _actionStreams.add(LogNotification('Found unknown device with identifier: ${data?.firstOrNull}'));
        }
      }
    };

    UniversalBle.onValueChange = (deviceId, characteristicUuid, value) {
      final device = devices.firstOrNullWhere((e) => e.device.deviceId == deviceId);
      if (device == null) {
        _actionStreams.add(LogNotification('Device not found: $deviceId'));
        UniversalBle.disconnect(deviceId);
        return;
      } else {
        device.processCharacteristic(characteristicUuid, value);
      }
    };
  }

  Future<void> performScanning() async {
    isScanning.value = true;
    _actionStreams.add(LogNotification('Scanning for devices...'));

    // does not work on web, may not work on Windows
    if (!kIsWeb && !Platform.isWindows) {
      UniversalBle.getSystemDevices(
        withServices: BaseDevice.servicesToScan,
      ).then((devices) async {
        final baseDevices = devices.mapNotNull(BaseDevice.fromScanResult).toList();
        if (baseDevices.isNotEmpty) {
          _addDevices(baseDevices);
        }
      });
    }

    await UniversalBle.startScan(
      scanFilter: ScanFilter(withServices: BaseDevice.servicesToScan),
      platformConfig: PlatformConfig(web: WebOptions(optionalServices: BaseDevice.servicesToScan)),
    );
    Future.delayed(Duration(seconds: 30)).then((_) {
      if (isScanning.value) {
        UniversalBle.stopScan();
        isScanning.value = false;
      }
    });
  }

  void _addDevices(List<BaseDevice> dev) {
    final newDevices = dev.where((device) => !devices.contains(device)).toList();
    devices.addAll(newDevices);

    _connectionQueue.addAll(newDevices);
    _handleConnectionQueue();

    hasDevices.value = devices.isNotEmpty;
    if (devices.isNotEmpty && !_androidNotificationsSetup && !kIsWeb && Platform.isAndroid) {
      _androidNotificationsSetup = true;
      NotificationRequirement.setup().catchError((e) {
        _actionStreams.add(LogNotification(e.toString()));
      });
    }
  }

  void _handleConnectionQueue() {
    // windows apparently has issues when connecting to multiple devices at once, so don't
    if (_connectionQueue.isNotEmpty && !_handlingConnectionQueue) {
      _handlingConnectionQueue = true;
      final device = _connectionQueue.removeAt(0);
      _actionStreams.add(LogNotification('Connecting to: ${device.device.name ?? device.runtimeType}'));
      _connect(device)
          .then((_) {
            _handlingConnectionQueue = false;
            _actionStreams.add(LogNotification('Connection finished: ${device.device.name ?? device.runtimeType}'));
            if (_connectionQueue.isNotEmpty) {
              _handleConnectionQueue();
            }
          })
          .catchError((e) {
            _handlingConnectionQueue = false;
            _actionStreams.add(LogNotification('Connection failed: ${device.device.name ?? device.runtimeType} - $e'));
            if (_connectionQueue.isNotEmpty) {
              _handleConnectionQueue();
            }
          });
    }
  }

  Future<void> _connect(BaseDevice bleDevice) async {
    try {
      final actionSubscription = bleDevice.actionStream.listen((data) {
        _actionStreams.add(data);
      });
      final connectionStateSubscription = UniversalBle.connectionStream(bleDevice.device.deviceId).listen((state) {
        bleDevice.isConnected = state;
        _connectionStreams.add(bleDevice);
        if (!bleDevice.isConnected) {
          devices.remove(bleDevice);
          _streamSubscriptions[bleDevice]?.cancel();
          _streamSubscriptions.remove(bleDevice);
          _connectionSubscriptions[bleDevice]?.cancel();
          _connectionSubscriptions.remove(bleDevice);
          _lastScanResult.clear();
          // try reconnect
          if (!isScanning.value) {
            performScanning();
          }
        }
      });
      _connectionSubscriptions[bleDevice] = connectionStateSubscription;

      await bleDevice.connect();

      _streamSubscriptions[bleDevice] = actionSubscription;
    } catch (e, backtrace) {
      _actionStreams.add(LogNotification("$e\n$backtrace"));
      if (kDebugMode) {
        print(e);
        print("backtrace: $backtrace");
      }
      rethrow;
    }
  }

  void reset() {
    _actionStreams.add(LogNotification('Disconnecting all devices'));
    if (actionHandler is AndroidActions) {
      AndroidFlutterLocalNotificationsPlugin().stopForegroundService();
      _androidNotificationsSetup = false;
    }
    UniversalBle.stopScan();
    isScanning.value = false;
    for (var device in devices) {
      _streamSubscriptions[device]?.cancel();
      _streamSubscriptions.remove(device);
      _connectionSubscriptions[device]?.cancel();
      _connectionSubscriptions.remove(device);
      UniversalBle.disconnect(device.device.deviceId);
      signalChange(device);
    }
    _lastScanResult.clear();
    hasDevices.value = false;
    devices.clear();
  }

  void signalNotification(BaseNotification notification) {
    _actionStreams.add(notification);
  }

  void signalChange(BaseDevice baseDevice) {
    _connectionStreams.add(baseDevice);
  }
}
