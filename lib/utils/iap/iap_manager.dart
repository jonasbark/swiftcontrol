import 'dart:io';

import 'package:bike_control/gen/l10n.dart';
import 'package:bike_control/main.dart';
import 'package:bike_control/utils/iap/revenuecat_service.dart';
import 'package:bike_control/utils/iap/windows_iap_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Unified IAP manager that handles platform-specific IAP services
class IAPManager {
  static IAPManager? _instance;
  static IAPManager get instance {
    _instance ??= IAPManager._();
    return _instance!;
  }

  static int dailyCommandLimit = 15;
  RevenueCatService? _revenueCatService;
  WindowsIAPService? _windowsIapService;
  ValueNotifier<bool> isPurchased = ValueNotifier<bool>(false);

  IAPManager._();

  /// Initialize the IAP manager
  Future<void> initialize() async {
    final prefs = FlutterSecureStorage(aOptions: AndroidOptions());

    if (kIsWeb || screenshotMode) {
      // Web doesn't support IAP
      return;
    }

    try {
      if (Platform.isWindows) {
        _windowsIapService = WindowsIAPService(prefs);
        await _windowsIapService!.initialize();
      } else if (Platform.isIOS || Platform.isMacOS || Platform.isAndroid) {
        _revenueCatService = RevenueCatService(prefs);
        await _revenueCatService!.initialize();
      }
    } catch (e) {
      debugPrint('Error initializing IAP manager: $e');
    }
  }

  /// Check if the trial period has started
  bool get hasTrialStarted {
    if (_revenueCatService != null) {
      return _revenueCatService!.hasTrialStarted;
    } else if (_windowsIapService != null) {
      return _windowsIapService!.hasTrialStarted;
    }
    return false;
  }

  /// Start the trial period
  Future<void> startTrial() async {
    if (_revenueCatService != null) {
      await _revenueCatService!.startTrial();
    }
  }

  /// Get the number of days remaining in the trial
  int get trialDaysRemaining {
    if (_revenueCatService != null) {
      return _revenueCatService!.trialDaysRemaining;
    } else if (_windowsIapService != null) {
      return _windowsIapService!.trialDaysRemaining;
    }
    return 0;
  }

  /// Check if the trial has expired
  bool get isTrialExpired {
    if (_revenueCatService != null) {
      return _revenueCatService!.isTrialExpired;
    } else if (_windowsIapService != null) {
      return _windowsIapService!.isTrialExpired;
    }
    return false;
  }

  /// Check if the user can execute a command
  bool get canExecuteCommand {
    // If IAP is not initialized or not available, allow commands
    if (_revenueCatService == null && _windowsIapService == null) return true;

    if (_revenueCatService != null) {
      return _revenueCatService!.canExecuteCommand;
    } else if (_windowsIapService != null) {
      return _windowsIapService!.canExecuteCommand;
    }
    return true; // Default to true for platforms without IAP
  }

  /// Get the number of commands remaining today (for free tier after trial)
  int get commandsRemainingToday {
    if (_revenueCatService != null) {
      return _revenueCatService!.commandsRemainingToday;
    } else if (_windowsIapService != null) {
      return _windowsIapService!.commandsRemainingToday;
    }
    return -1; // Unlimited
  }

  /// Get the daily command count
  int get dailyCommandCount {
    if (_revenueCatService != null) {
      return _revenueCatService!.dailyCommandCount;
    } else if (_windowsIapService != null) {
      return _windowsIapService!.dailyCommandCount;
    }
    return 0;
  }

  /// Increment the daily command count
  Future<void> incrementCommandCount() async {
    if (_revenueCatService != null) {
      await _revenueCatService!.incrementCommandCount();
    } else if (_windowsIapService != null) {
      await _windowsIapService!.incrementCommandCount();
    }
  }

  /// Get a status message for the user
  String getStatusMessage() {
    /// Get a status message for the user
    if (IAPManager.instance.isPurchased.value) {
      return AppLocalizations.current.fullVersion;
    } else if (!hasTrialStarted) {
      return '${_revenueCatService?.trialDaysRemaining ?? _windowsIapService?.trialDaysRemaining} day trial available';
    } else if (!isTrialExpired) {
      return AppLocalizations.current.trialDaysRemaining(trialDaysRemaining);
    } else {
      return AppLocalizations.current.commandsRemainingToday(commandsRemainingToday, dailyCommandLimit);
    }
  }

  /// Purchase the full version
  Future<void> purchaseFullVersion() async {
    if (_revenueCatService != null) {
      return await _revenueCatService!.purchaseFullVersion();
    } else if (_windowsIapService != null) {
      return await _windowsIapService!.purchaseFullVersion();
    }
  }

  /// Restore previous purchases
  Future<void> restorePurchases() async {
    if (_revenueCatService != null) {
      await _revenueCatService!.restorePurchases();
    }
    // Windows doesn't have a separate restore mechanism in the stub
  }

  /// Dispose the manager
  void dispose() {
    _revenueCatService?.dispose();
    _windowsIapService?.dispose();
  }

  /// Reset IAP state
  /// Note: Windows reset is synchronous (simple delete), RevenueCat reset is async (includes reinit)
  Future<void> reset(bool fullReset) async {
    _windowsIapService?.reset();
    await _revenueCatService?.reset(fullReset);
  }

  Future<void> redeem() async {
    await _revenueCatService!.redeem();
  }
}
