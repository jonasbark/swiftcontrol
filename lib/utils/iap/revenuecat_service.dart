import 'dart:async';
import 'dart:io';

import 'package:bike_control/bluetooth/devices/zwift/protocol/zp.pb.dart';
import 'package:bike_control/bluetooth/messages/notification.dart';
import 'package:bike_control/main.dart';
import 'package:bike_control/utils/core.dart';
import 'package:bike_control/utils/iap/iap_manager.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:intl/intl.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:version/version.dart';

/// Service to handle in-app purchase functionality using RevenueCat SDK
/// 
/// Configuration requirements:
/// - RevenueCat entitlement: 'full_access'
/// - Product ID (App Store/Google Play): 'full_access_unlock'
/// - API keys must be provided via environment variables:
///   - REVENUECAT_IOS_API_KEY for iOS and macOS
///   - REVENUECAT_ANDROID_API_KEY for Android
class RevenueCatService {
  static const int trialDays = 5;

  static const String _trialStartDateKey = 'iap_trial_start_date';
  static const String _purchaseStatusKey = 'iap_purchase_status';
  static const String _dailyCommandCountKey = 'iap_daily_command_count';
  static const String _lastCommandDateKey = 'iap_last_command_date';
  static const String _lastPurchaseCheckKey = 'iap_last_purchase_check';
  static const String _hasPurchasedKey = 'iap_has_purchased';

  final FlutterSecureStorage _prefs;

  StreamSubscription<CustomerInfo>? _subscription;
  bool _isInitialized = false;
  String? _trialStartDate;
  String? _lastCommandDate;
  int? _dailyCommandCount;

  RevenueCatService(this._prefs);

  /// Initialize the RevenueCat service
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      // Skip IAP initialization on web
      if (kIsWeb) {
        debugPrint('IAP not supported on web');
        _isInitialized = true;
        return;
      }

      // Configure RevenueCat with platform-specific API keys
      PurchasesConfiguration configuration;
      if (Platform.isIOS) {
        // iOS API key from RevenueCat dashboard
        const apiKey = String.fromEnvironment(
          'REVENUECAT_IOS_API_KEY',
          defaultValue: '',
        );
        if (apiKey.isEmpty) {
          debugPrint('RevenueCat iOS API key not configured');
          IAPManager.instance.isPurchased.value = false;
          _isInitialized = true;
          return;
        }
        configuration = PurchasesConfiguration(apiKey);
      } else if (Platform.isAndroid) {
        // Android API key from RevenueCat dashboard
        const apiKey = String.fromEnvironment(
          'REVENUECAT_ANDROID_API_KEY',
          defaultValue: '',
        );
        if (apiKey.isEmpty) {
          debugPrint('RevenueCat Android API key not configured');
          IAPManager.instance.isPurchased.value = false;
          _isInitialized = true;
          return;
        }
        configuration = PurchasesConfiguration(apiKey);
      } else if (Platform.isMacOS) {
        // macOS uses the same API key as iOS
        const apiKey = String.fromEnvironment(
          'REVENUECAT_IOS_API_KEY',
          defaultValue: '',
        );
        if (apiKey.isEmpty) {
          debugPrint('RevenueCat macOS API key not configured');
          IAPManager.instance.isPurchased.value = false;
          _isInitialized = true;
          return;
        }
        configuration = PurchasesConfiguration(apiKey);
      } else {
        debugPrint('RevenueCat not supported on this platform');
        IAPManager.instance.isPurchased.value = false;
        _isInitialized = true;
        return;
      }

      // Enable debug logs in development
      if (kDebugMode) {
        configuration = configuration.copyWith(logLevel: LogLevel.debug);
      }

      await Purchases.configure(configuration);

      // Listen for purchase updates
      _subscription = Purchases.addCustomerInfoUpdateListener(_onCustomerInfoUpdate);

      _trialStartDate = await _prefs.read(key: _trialStartDateKey);
      core.connection.signalNotification(LogNotification('Trial start date: $_trialStartDate => $trialDaysRemaining'));

      _lastCommandDate = await _prefs.read(key: _lastCommandDateKey);

      final commandCount = await _prefs.read(key: _dailyCommandCountKey) ?? '0';
      _dailyCommandCount = int.tryParse(commandCount);

      // Check if already purchased
      await _checkExistingPurchase();

      _isInitialized = true;

      if (!isTrialExpired && Platform.isAndroid) {
        IAPManager.dailyCommandLimit = 80;
      }
    } catch (e, s) {
      recordError(e, s, context: 'Initializing RevenueCat Service');
      core.connection.signalNotification(
        AlertNotification(LogLevel.LOGLEVEL_ERROR, 'There was an error checking purchase status: ${e.toString()}'),
      );
      debugPrint('Failed to initialize RevenueCat: $e');
      // On initialization failure, default to allowing access
      IAPManager.instance.isPurchased.value = false;
      _isInitialized = true;
    }
  }

  /// Check if the user has already purchased the app
  Future<void> _checkExistingPurchase() async {
    // First check if we have a stored purchase status
    final storedStatus = await _prefs.read(key: _purchaseStatusKey);
    final lastPurchaseCheck = await _prefs.read(key: _lastPurchaseCheckKey);
    final hasPurchased = await _prefs.read(key: _hasPurchasedKey);

    String todayDate = DateFormat('yyyy-MM-dd').format(DateTime.now());

    if (storedStatus == "true") {
      if (Platform.isAndroid) {
        if (lastPurchaseCheck == todayDate || hasPurchased == null) {
          // hasPurchased means it was redeemed manually, so we skip the daily check
          IAPManager.instance.isPurchased.value = true;
        }
      } else {
        IAPManager.instance.isPurchased.value = true;
      }
      return;
    }

    await _prefs.write(key: _lastPurchaseCheckKey, value: todayDate);

    // Platform-specific checks for existing paid app purchases
    if (Platform.isIOS || Platform.isMacOS) {
      // On iOS/macOS, check if the app was previously purchased (legacy check)
      await _checkLegacyPurchase();
    } else if (Platform.isAndroid) {
      // On Android, check if user had the paid version before
      await _checkAndroidPreviousPurchase();
    }

    // Check RevenueCat for active entitlements
    if (!IAPManager.instance.isPurchased.value) {
      await _checkRevenueCatEntitlements();
    }
  }

  /// Check for legacy purchases (before RevenueCat integration)
  Future<void> _checkLegacyPurchase() async {
    try {
      // Legacy check logic can be kept for existing users
      // This preserves the existing logic for users who purchased before RevenueCat
      final lastSeenVersion = core.settings.getLastSeenVersion();
      if (lastSeenVersion != null && lastSeenVersion.isNotEmpty) {
        Version lastVersion = Version.parse(lastSeenVersion);
        if (Platform.isIOS && lastVersion < Version(4, 2, 0)) {
          IAPManager.instance.isPurchased.value = true;
          await _prefs.write(key: _purchaseStatusKey, value: "true");
          debugPrint('Legacy iOS user detected - granting full access');
        } else if (Platform.isMacOS && lastVersion < Version(4, 2, 0)) {
          IAPManager.instance.isPurchased.value = true;
          await _prefs.write(key: _purchaseStatusKey, value: "true");
          debugPrint('Legacy macOS user detected - granting full access');
        }
      }
    } catch (e) {
      debugPrint('Error checking legacy purchase: $e');
    }
  }

  /// Check if Android user had the paid app before
  Future<void> _checkAndroidPreviousPurchase() async {
    try {
      final lastSeenVersion = core.settings.getLastSeenVersion();
      core.connection.signalNotification(LogNotification('Android last seen version: $lastSeenVersion'));
      if (lastSeenVersion != null && lastSeenVersion.isNotEmpty) {
        Version lastVersion = Version.parse(lastSeenVersion);
        // If they had a previous version, they're an existing paid user
        IAPManager.instance.isPurchased.value = lastVersion < Version(4, 2, 0);
        if (IAPManager.instance.isPurchased.value) {
          await _prefs.write(key: _purchaseStatusKey, value: "true");
        }
        debugPrint('Existing Android user detected - granting full access');
      }
    } catch (e, s) {
      debugPrint('Error checking Android previous purchase: $e');
      recordError(e, s, context: 'Checking Android previous purchase');
    }
  }

  /// Check RevenueCat for active entitlements
  Future<void> _checkRevenueCatEntitlements() async {
    try {
      final customerInfo = await Purchases.getCustomerInfo();
      _updatePurchaseStatus(customerInfo);
    } catch (e) {
      debugPrint('Error checking RevenueCat entitlements: $e');
      core.connection.signalNotification(
        LogNotification('There was an error checking RevenueCat entitlements: ${e.toString()}'),
      );
    }
  }

  /// Handle customer info updates from RevenueCat
  void _onCustomerInfoUpdate(CustomerInfo customerInfo) {
    core.connection.signalNotification(
      LogNotification('RevenueCat customer info updated'),
    );
    _updatePurchaseStatus(customerInfo);
  }

  /// Update purchase status based on customer info
  void _updatePurchaseStatus(CustomerInfo customerInfo) {
    // Check if the user has the "full_access" entitlement
    final hasFullAccess = customerInfo.entitlements.active.containsKey('full_access');
    
    if (hasFullAccess) {
      IAPManager.instance.isPurchased.value = true;
      _prefs.write(key: _hasPurchasedKey, value: "true");
      _prefs.write(key: _purchaseStatusKey, value: "true");
      debugPrint('RevenueCat: User has full access');
    } else {
      debugPrint('RevenueCat: User does not have full access');
    }
  }

  /// Restore previous purchases using RevenueCat
  Future<void> restorePurchases() async {
    try {
      final customerInfo = await Purchases.restorePurchases();
      _updatePurchaseStatus(customerInfo);
      core.connection.signalNotification(
        LogNotification('Purchases restored successfully'),
      );
    } catch (e, s) {
      core.connection.signalNotification(
        AlertNotification(LogLevel.LOGLEVEL_ERROR, 'There was an error restoring purchases: ${e.toString()}'),
      );
      recordError(e, s, context: 'Restore Purchases');
      debugPrint('Error restoring purchases: $e');
    }
  }

  /// Purchase the full version using RevenueCat
  Future<void> purchaseFullVersion() async {
    try {
      if (!_isInitialized) {
        await initialize();
      }

      // Get available offerings from RevenueCat
      final offerings = await Purchases.getOfferings();
      
      if (offerings.current == null) {
        debugPrint('No current offering available');
        core.connection.signalNotification(
          AlertNotification(LogLevel.LOGLEVEL_INFO, 'No products available for purchase.'),
        );
        return;
      }

      // Get the lifetime package or the first available package
      final package = offerings.current!.lifetime ?? 
                     offerings.current!.availablePackages.firstOrNull;
      
      if (package == null) {
        debugPrint('No package available');
        core.connection.signalNotification(
          AlertNotification(LogLevel.LOGLEVEL_INFO, 'No products available for purchase.'),
        );
        return;
      }

      // Purchase the package
      final purchaseResult = await Purchases.purchasePackage(package);
      _updatePurchaseStatus(purchaseResult.customerInfo);
      
      core.connection.signalNotification(
        LogNotification('Purchase completed successfully'),
      );
    } catch (e, s) {
      if (e is PlatformException) {
        final errorCode = PurchasesErrorHelper.getErrorCode(e);
        if (errorCode == PurchasesErrorCode.purchaseCancelledError) {
          debugPrint('Purchase cancelled by user');
          core.connection.signalNotification(
            LogNotification('Purchase was cancelled'),
          );
          return;
        }
      }
      
      debugPrint('Error purchasing: $e');
      recordError(e, s, context: 'Error purchasing');
      core.connection.signalNotification(
        AlertNotification(LogLevel.LOGLEVEL_ERROR, 'There was an error during purchasing: ${e.toString()}'),
      );
    }
  }

  /// Check if the trial period has started
  bool get hasTrialStarted {
    return _trialStartDate != null;
  }

  /// Start the trial period
  Future<void> startTrial() async {
    if (!hasTrialStarted) {
      await _prefs.write(key: _trialStartDateKey, value: DateTime.now().toIso8601String());
    }
  }

  /// Get the number of days remaining in the trial
  int get trialDaysRemaining {
    if (IAPManager.instance.isPurchased.value) return 0;

    final trialStart = _trialStartDate;
    if (trialStart == null) return trialDays;

    final startDate = DateTime.parse(trialStart);
    final now = DateTime.now();
    final daysPassed = now.difference(startDate).inDays;
    final remaining = trialDays - daysPassed;

    return remaining > 0 ? remaining : 0;
  }

  /// Check if the trial has expired
  bool get isTrialExpired {
    return (!IAPManager.instance.isPurchased.value && hasTrialStarted && trialDaysRemaining <= 0);
  }

  /// Get the number of commands executed today
  int get dailyCommandCount {
    final lastDate = _lastCommandDate;
    final today = DateTime.now().toIso8601String().split('T')[0];

    if (lastDate != today) {
      // Reset counter for new day
      _lastCommandDate = today;
      _dailyCommandCount = 0;
    }

    return _dailyCommandCount ?? 0;
  }

  /// Increment the daily command count
  Future<void> incrementCommandCount() async {
    final today = DateTime.now().toIso8601String().split('T')[0];
    final lastDate = await _prefs.read(key: _lastCommandDateKey);

    if (lastDate != today) {
      // Reset counter for new day
      _lastCommandDate = today;
      _dailyCommandCount = 1;
      await _prefs.write(key: _lastCommandDateKey, value: today);
      await _prefs.write(key: _dailyCommandCountKey, value: '1');
    } else {
      final count = _dailyCommandCount ?? 0;
      _dailyCommandCount = count + 1;
      await _prefs.write(key: _dailyCommandCountKey, value: _dailyCommandCount.toString());
    }
  }

  /// Check if the user can execute a command
  bool get canExecuteCommand {
    if (IAPManager.instance.isPurchased.value) return true;
    if (!isTrialExpired && !Platform.isAndroid) return true;
    return dailyCommandCount < IAPManager.dailyCommandLimit;
  }

  /// Get the number of commands remaining today (for free tier after trial)
  int get commandsRemainingToday {
    if (IAPManager.instance.isPurchased.value || (!isTrialExpired && !Platform.isAndroid)) return -1; // Unlimited
    final remaining = IAPManager.dailyCommandLimit - dailyCommandCount;
    return remaining > 0 ? remaining : 0; // Never return negative
  }

  /// Dispose the service
  void dispose() {
    _subscription?.cancel();
  }

  void reset(bool fullReset) {
    if (fullReset) {
      _prefs.deleteAll();
    } else {
      _prefs.delete(key: _purchaseStatusKey);
      _isInitialized = false;
      initialize();
    }
  }

  Future<void> redeem() async {
    IAPManager.instance.isPurchased.value = true;
    await _prefs.write(key: _purchaseStatusKey, value: IAPManager.instance.isPurchased.value.toString());
  }
}
