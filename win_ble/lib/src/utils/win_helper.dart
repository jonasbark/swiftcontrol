/// This class is used to store the device map and subscription map
/// and some other helper methods
class WinHelper {
  static Map deviceMap = {};
  static Map<String, Map<String, String>> subscriptions = {};
  static bool showLog = false;

  /// enableLog in [initialize] method
  static void printLog(log) {
    // ignore: avoid_print
    if (showLog) print(log);
  }

  static String toWindowsUuid(String uuid) => "{$uuid}";

  static String fromWindowsUuid(String uuid) =>
      uuid.replaceAll("{", "").replaceAll("}", "");

  static String getDeviceFromAddress(String address) {
    if (deviceMap[address] == null) {
      throw "Device not found !";
    } else {
      return deviceMap[address];
    }
  }

  static String? getAddressFromDevice(String device) {
    String? address;
    deviceMap.forEach((key, value) {
      if (value == device) {
        address = key;
      }
    });
    return address;
  }

  static Map<String, String>? getDataFromSubscriptionKey(subscriptionKey) {
    try {
      Map<String, String> data = {};
      if (subscriptions.isEmpty) return null;
      subscriptions.forEach((key, value) {
        if (key == subscriptionKey) {
          data = value;
        }
      });
      return data.isEmpty ? null : data;
    } catch (e) {
      printLog("Error in _getSubscriptionKey :  $e");
      return null;
    }
  }
}
