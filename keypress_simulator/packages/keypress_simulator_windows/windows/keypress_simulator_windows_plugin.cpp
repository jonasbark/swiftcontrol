#include "keypress_simulator_windows_plugin.h"

// This must be included before many other Windows headers.
#include <windows.h>
#include <psapi.h>
#include <string.h>
#include <flutter_windows.h>

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>

#include <memory>
#include <sstream>

using flutter::EncodableList;
using flutter::EncodableMap;
using flutter::EncodableValue;

namespace keypress_simulator_windows {

// Forward declarations
struct FindWindowData {
  std::string targetProcessName;
  std::string targetWindowTitle;
  HWND foundWindow;
};

BOOL CALLBACK EnumWindowsCallback(HWND hwnd, LPARAM lParam);
HWND FindTargetWindow(const std::string& processName, const std::string& windowTitle);

// static
void KeypressSimulatorWindowsPlugin::RegisterWithRegistrar(
    flutter::PluginRegistrarWindows* registrar) {
  auto channel =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          registrar->messenger(), "dev.leanflutter.plugins/keypress_simulator",
          &flutter::StandardMethodCodec::GetInstance());

  auto plugin = std::make_unique<KeypressSimulatorWindowsPlugin>();

  channel->SetMethodCallHandler(
      [plugin_pointer = plugin.get()](const auto& call, auto result) {
        plugin_pointer->HandleMethodCall(call, std::move(result));
      });

  registrar->AddPlugin(std::move(plugin));
}

KeypressSimulatorWindowsPlugin::KeypressSimulatorWindowsPlugin() {}

KeypressSimulatorWindowsPlugin::~KeypressSimulatorWindowsPlugin() {}

void KeypressSimulatorWindowsPlugin::SimulateKeyPress(
    const flutter::MethodCall<flutter::EncodableValue>& method_call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  const EncodableMap& args = std::get<EncodableMap>(*method_call.arguments());

  UINT keyCode = std::get<int>(args.at(EncodableValue("keyCode")));
  std::vector<std::string> modifiers;
  bool keyDown = std::get<bool>(args.at(EncodableValue("keyDown")));

  EncodableList key_modifier_list =
      std::get<EncodableList>(args.at(EncodableValue("modifiers")));
  for (flutter::EncodableValue key_modifier_value : key_modifier_list) {
    std::string key_modifier = std::get<std::string>(key_modifier_value);
    modifiers.push_back(key_modifier);
  }

  // Check if this is a media key (USB HID Consumer Page: 0x000C0000 range)
  bool isMediaKey = (keyCode & 0xFFFF0000) == 0x000C0000;
  UINT vkCode = 0;
  
  if (isMediaKey) {
    // Map USB HID media key codes to Windows VK codes
    UINT hidUsage = keyCode & 0xFFFF;
    switch (hidUsage) {
      case 0x00E8: vkCode = VK_MEDIA_PLAY_PAUSE; break;  // mediaPlayPause
      case 0x00B5: vkCode = VK_MEDIA_NEXT_TRACK; break;  // mediaTrackNext
      case 0x00B6: vkCode = VK_MEDIA_PREV_TRACK; break;  // mediaTrackPrevious
      case 0x00B7: vkCode = VK_MEDIA_STOP; break;        // mediaStop
      case 0x00E9: vkCode = VK_VOLUME_UP; break;         // audioVolumeUp
      case 0x00EA: vkCode = VK_VOLUME_DOWN; break;       // audioVolumeDown
      default:
        // Unknown media key, try to continue with regular handling
        isMediaKey = false;
        break;
    }
  }

  INPUT in = {0};
  in.type = INPUT_KEYBOARD;

  if (isMediaKey) {
    // For media keys, use VK code directly
    in.ki.wVk = vkCode;
    in.ki.wScan = 0;
    in.ki.dwFlags = (keyDown ? 0 : KEYEVENTF_KEYUP);
  } else {
    // For regular keys, focus compatible apps and use scan code
    // List of compatible training apps to look for
    std::vector<std::string> compatibleApps = {
      "MyWhooshHD.exe",
      "indieVelo.exe",
      "biketerra.exe"
    };

    // Try to find and focus a compatible app
    HWND targetWindow = NULL;
    for (const std::string& processName : compatibleApps) {
      targetWindow = FindTargetWindow(processName, "");
      if (targetWindow != NULL) {
        // Only focus the window if it's not already in the foreground
        if (GetForegroundWindow() != targetWindow) {
          SetForegroundWindow(targetWindow);
          Sleep(50); // Brief delay to ensure window is focused
        }
        break;
      }
    }

    WORD sc = (WORD)MapVirtualKey(keyCode, MAPVK_VK_TO_VSC);
    in.ki.wVk = 0;                 // when using SCANCODE, set VK=0
    in.ki.wScan = sc;
    in.ki.dwFlags = KEYEVENTF_SCANCODE | (keyDown ? 0 : KEYEVENTF_KEYUP);
    if (keyCode == VK_LEFT || keyCode == VK_RIGHT || keyCode == VK_UP || keyCode == VK_DOWN ||
      keyCode == VK_INSERT || keyCode == VK_DELETE || keyCode == VK_HOME || keyCode == VK_END ||
      keyCode == VK_PRIOR || keyCode == VK_NEXT) {
      in.ki.dwFlags |= KEYEVENTF_EXTENDEDKEY;
    }
  }

  SendInput(1, &in, sizeof(INPUT));

  result->Success(flutter::EncodableValue(true));
}

void KeypressSimulatorWindowsPlugin::SimulateMouseClick(
    const flutter::MethodCall<flutter::EncodableValue>& method_call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {

  const EncodableMap& args = std::get<EncodableMap>(*method_call.arguments());
  double x = 0;
  double y = 0;

  bool keyDown = std::get<bool>(args.at(EncodableValue("keyDown")));
  auto it_x = args.find(EncodableValue("x"));
  if (it_x != args.end() && std::holds_alternative<double>(it_x->second)) {
      x = std::get<double>(it_x->second);
  }

  auto it_y = args.find(EncodableValue("y"));
  if (it_y != args.end() && std::holds_alternative<double>(it_y->second)) {
      y = std::get<double>(it_y->second);
  }

  // Get the monitor containing the target point and its DPI
  const POINT target_point = {static_cast<LONG>(x), static_cast<LONG>(y)};
  HMONITOR monitor = MonitorFromPoint(target_point, MONITOR_DEFAULTTONEAREST);
  UINT dpi = FlutterDesktopGetDpiForMonitor(monitor);
  double scale_factor = dpi / 96.0;
  
  // Scale the coordinates according to the DPI scaling
  int scaled_x = static_cast<int>(x * scale_factor);
  int scaled_y = static_cast<int>(y * scale_factor);

  // Move the mouse to the specified coordinates
  SetCursorPos(scaled_x, scaled_y);

  // Prepare input for mouse down and up
  INPUT input = {0};
  input.type = INPUT_MOUSE;

  if (keyDown) {
      // Mouse left button down
      input.mi.dwFlags = MOUSEEVENTF_LEFTDOWN;
      SendInput(1, &input, sizeof(INPUT));

  } else {
      // Mouse left button up
      input.mi.dwFlags = MOUSEEVENTF_LEFTUP;
      SendInput(1, &input, sizeof(INPUT));
  }

  result->Success(flutter::EncodableValue(true));
}

BOOL CALLBACK EnumWindowsCallback(HWND hwnd, LPARAM lParam) {
  FindWindowData* data = reinterpret_cast<FindWindowData*>(lParam);

  // Check if window is visible and not minimized
  if (!IsWindowVisible(hwnd) || IsIconic(hwnd)) {
    return TRUE; // Continue enumeration
  }

  // Get window title
  char windowTitle[256];
  GetWindowTextA(hwnd, windowTitle, sizeof(windowTitle));

  // Get process name
  DWORD processId;
  GetWindowThreadProcessId(hwnd, &processId);
  HANDLE hProcess = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, processId);
  char processName[MAX_PATH];
  if (hProcess) {
    DWORD size = sizeof(processName);
    if (QueryFullProcessImageNameA(hProcess, 0, processName, &size)) {
      // Extract just the filename from the full path
      char* filename = strrchr(processName, '\\');
      if (filename) {
        filename++; // Skip the backslash
      } else {
        filename = processName;
      }

      // Check if this matches our target
      if (!data->targetProcessName.empty() &&
          _stricmp(filename, data->targetProcessName.c_str()) == 0) {
        data->foundWindow = hwnd;
        return FALSE; // Stop enumeration
      }
    }
    CloseHandle(hProcess);
  }

  // Check window title if process name didn't match
  if (!data->targetWindowTitle.empty() &&
      _stricmp(windowTitle, data->targetWindowTitle.c_str()) == 0) {
    data->foundWindow = hwnd;
    return FALSE; // Stop enumeration
  }

  return TRUE; // Continue enumeration
}

HWND FindTargetWindow(const std::string& processName, const std::string& windowTitle) {
  FindWindowData data;
  data.targetProcessName = processName;
  data.targetWindowTitle = windowTitle;
  data.foundWindow = NULL;

  EnumWindows(EnumWindowsCallback, reinterpret_cast<LPARAM>(&data));
  return data.foundWindow;
}



void KeypressSimulatorWindowsPlugin::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue>& method_call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  if (method_call.method_name().compare("simulateKeyPress") == 0) {
    SimulateKeyPress(method_call, std::move(result));
  } else if (method_call.method_name().compare("simulateMouseClick") == 0) {
    SimulateMouseClick(method_call, std::move(result));
  } else {
    result->NotImplemented();
  }
}

}  // namespace keypress_simulator_windows
