import 'dart:io';

import 'package:bike_control/bluetooth/devices/mdns_emulator.dart';
import 'package:bike_control/bluetooth/devices/openbikecontrol/openbikecontrol_device.dart';
import 'package:bike_control/bluetooth/devices/openbikecontrol/protocol_parser.dart';
import 'package:bike_control/bluetooth/messages/notification.dart';
import 'package:bike_control/utils/actions/base_actions.dart';
import 'package:bike_control/utils/core.dart';
import 'package:bike_control/utils/keymap/buttons.dart';
import 'package:bike_control/utils/keymap/keymap.dart';
import 'package:dartx/dartx.dart';
import 'package:flutter/foundation.dart';
import 'package:nsd/nsd.dart';

class OpenBikeControlMdnsEmulator extends MdnsEmulator {
  static const String connectionTitle = 'OpenBikeControl mDNS Emulator';

  final ValueNotifier<AppInfo?> connectedApp = ValueNotifier(null);

  OpenBikeControlMdnsEmulator()
    : super(
        title: connectionTitle,
        supportedActions: InGameAction.values,
      );

  Future<void> startServer() async {
    print('Starting mDNS server...');
    isStarted.value = true;

    // Get local IP
    final localIP = await findLocalIP();

    if (localIP == null) {
      throw 'Could not find network interface';
    }

    await _createTcpServer();

    try {
      // Create service
      await registerMdnsService(
        Service(
          name: 'BikeControl',
          type: '_openbikecontrol._tcp',
          port: 36867,
          //hostName: 'KICKR BIKE SHIFT B84D.local',
          addresses: [localIP],
          txt: {
            'version': Uint8List.fromList([0x01]),
            'id': Uint8List.fromList('1337'.codeUnits),
            'name': Uint8List.fromList('BikeControl'.codeUnits),
            'service-uuids': Uint8List.fromList(OpenBikeControlConstants.SERVICE_UUID.codeUnits),
            'manufacturer': Uint8List.fromList('OpenBikeControl'.codeUnits),
            'model': Uint8List.fromList('BikeControl app'.codeUnits),
          },
        ),
      );
      print('Service: ${mdnsRegistration!.id} at ${localIP.address}:$mdnsRegistration');
      print('Server started - advertising service!');
    } catch (e, s) {
      core.connection.signalNotification(AlertNotification(LogLevel.LOGLEVEL_ERROR, 'Failed to start mDNS server: $e'));
      rethrow;
    }
  }

  Future<void> stopServer() async {
    if (kDebugMode) {
      print('Stopping OpenBikeControl mDNS server...');
    }
    stop();
    connectedApp.value = null;
  }

  Future<void> _createTcpServer() async {
    await createTcpServer(36867);

    // Accept connection
    tcpServer!.listen(
      (Socket socket) {
        this.socket = socket;

        if (kDebugMode) {
          print('Client connected: ${socket.remoteAddress.address}:${socket.remotePort}');
        }

        // Listen for data from the client
        socket.listen(
          (List<int> data) {
            if (kDebugMode) {
              print('Received message: ${bytesToHex(data)}');
            }
            final messageType = data[0];
            switch (messageType) {
              case OpenBikeProtocolParser.MSG_TYPE_APP_INFO:
                final appInfo = OpenBikeProtocolParser.parseAppInfo(Uint8List.fromList(data));
                isConnected.value = true;
                connectedApp.value = appInfo;

                supportedActions = appInfo.supportedButtons.mapNotNull((b) => b.action).toList();
                core.connection.signalNotification(
                  AlertNotification(LogLevel.LOGLEVEL_INFO, 'Connected to app: ${appInfo.appId}'),
                );
                break;
              default:
                print('Unknown message type: $messageType');
            }
          },
          onDone: () {
            core.connection.signalNotification(
              AlertNotification(LogLevel.LOGLEVEL_INFO, 'Disconnected from app: ${connectedApp.value?.appId}'),
            );
            isConnected.value = false;
            connectedApp.value = null;
            this.socket = null;
          },
        );
      },
    );
  }

  @override
  Future<ActionResult> sendAction(KeyPair keyPair, {required bool isKeyDown, required bool isKeyUp}) async {
    final inGameAction = keyPair.inGameAction;

    final mappedButtons = connectedApp.value!.supportedButtons.filter(
      (supportedButton) => supportedButton.action == inGameAction,
    );

    if (inGameAction == null) {
      return Error('Invalid in-game action for key pair: $keyPair');
    } else if (socket == null) {
      print('No client connected, cannot send button press');
      return Error('No client connected');
    } else if (connectedApp.value == null) {
      return Error('No app info received from central');
    } else if (mappedButtons.isEmpty) {
      return NotHandled('App does not support: ${inGameAction.title}');
    }

    if (isKeyDown && isKeyUp) {
      final responseDataDown = OpenBikeProtocolParser.encodeButtonState(
        mappedButtons.map((b) => ButtonState(b, 1)).toList(),
      );
      writeToSocket(socket!, responseDataDown);
      final responseDataUp = OpenBikeProtocolParser.encodeButtonState(
        mappedButtons.map((b) => ButtonState(b, 0)).toList(),
      );
      writeToSocket(socket!, responseDataUp);
    } else {
      final responseData = OpenBikeProtocolParser.encodeButtonState(
        mappedButtons.map((b) => ButtonState(b, isKeyDown ? 1 : 0)).toList(),
      );
      writeToSocket(socket!, responseData);
    }

    return Success('Sent ${inGameAction.title} button press');
  }
}
