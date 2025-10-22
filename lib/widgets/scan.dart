import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:swift_control/main.dart';
import 'package:swift_control/pages/markdown.dart';
import 'package:swift_control/widgets/small_progress_indicator.dart';

import 'logviewer.dart';

class ScanWidget extends StatefulWidget {
  const ScanWidget({super.key});

  @override
  State<ScanWidget> createState() => _ScanWidgetState();
}

class _ScanWidgetState extends State<ScanWidget> {
  @override
  void initState() {
    super.initState();

    connection.initialize();

    /*_isScanningSubscription = FlutterBluePlus.isScanning.listen((state) {
      _isScanning = state;
      if (mounted) {
        setState(() {});
      }
    });*/

    // after the first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // must be called from a button
      if (!kIsWeb) {
        Future.delayed(Duration(seconds: 1))
            .then((_) {
              return connection.performScanning();
            })
            .catchError((e) {
              print(e);
            });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(minHeight: 200),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ValueListenableBuilder(
            valueListenable: connection.isScanning,
            builder: (context, isScanning, widget) {
              if (isScanning) {
                return Column(
                  spacing: 12,
                  mainAxisAlignment: MainAxisAlignment.start,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Scanning for devices... Make sure they are powered on and in range and not connected to another device.',
                    ),
                    TextButton(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (c) => MarkdownPage(assetPath: 'TROUBLESHOOTING.md')),
                        );
                      },
                      child: const Text("Show Troubleshooting Guide"),
                    ),
                    SmallProgressIndicator(),
                  ],
                );
              } else {
                return Row(
                  children: [
                    ElevatedButton(
                      onPressed: () {
                        connection.performScanning();
                      },
                      child: const Text("SCAN"),
                    ),
                  ],
                );
              }
            },
          ),
          if (kDebugMode && false) SizedBox(height: 500, child: LogViewer()),
        ],
      ),
    );
  }
}
