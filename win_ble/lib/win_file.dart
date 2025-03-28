import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

class WinServer {
  /// Get path of BleServer from library assets,
  ///  use this class in Flutter projects only, this class is not supported in pure Dart projects.
  /// use [fileName] to avoid conflicts of using same file in different projects
  static Future<String> path({String? fileName}) async {
    String bleServerExe = "packages/win_ble/assets/BLEServer.exe";
    File file = await _getFilePath(bleServerExe, fileName);
    return file.path;
  }

  static Future<File> _getFilePath(String path, String? fileName) async {
    final byteData = await rootBundle.load(path);
    final buffer = byteData.buffer;
    String tempPath = (await getTemporaryDirectory()).path;
    var initPath = '$tempPath/${fileName ?? 'win_ble_server'}.exe';
    var filePath = initPath;

    //Prevent multiple applications and file being occupied, max 10
    for (int i = 1; i < 10; i++) {
      var file = File(filePath);
      if (file.existsSync()) {
        try {
          file.deleteSync();
        } catch (e) {
          filePath = "$initPath$i";
          continue;
        }
        break;
      } else {
        break;
      }
    }

    return File(filePath).writeAsBytes(buffer.asUint8List(byteData.offsetInBytes, byteData.lengthInBytes));
  }
}
