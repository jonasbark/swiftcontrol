import 'dart:typed_data';

import 'package:bike_control/services/bonjour/bonjour_api.dart';

/// Records register()/deallocate() calls instead of touching dnssd.dll, so
/// [BonjourServiceAdvertiser] can report "available" (or, with
/// [isAvailable] false, "Bonjour not installed") off Windows. Shared by the
/// backend-selection test (Task 3) and the fix-dispatcher test (Task 10).
class FakeBonjourApi implements BonjourApi {
  FakeBonjourApi({this.isAvailable = true});

  @override
  bool isAvailable;

  int registerCallCount = 0;

  @override
  Object register({required String name, required String type, required int port, required Uint8List txtRecord}) {
    registerCallCount++;
    return Object();
  }

  @override
  void deallocate(Object handle) {}
}
