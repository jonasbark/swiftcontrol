# RevenueCat Integration Guide

This document explains the RevenueCat integration for in-app purchases on iOS, Android, and macOS platforms.

## Overview

BikeControl now uses RevenueCat SDK for managing in-app purchases across iOS, Android, and macOS platforms. RevenueCat provides:

- Cross-platform receipt validation
- Server-side purchase management
- Analytics and insights
- Subscription management
- Better user experience with unified APIs

## Configuration Steps

### 1. RevenueCat Dashboard Setup

1. Create a RevenueCat account at https://www.revenuecat.com/
2. Create a new project for BikeControl
3. Add your iOS, Android, and macOS apps to the project

### 2. Store Configuration

#### iOS/macOS (App Store Connect)
1. In App Store Connect, create an in-app purchase product with ID: `full_access_unlock`
2. Make it a non-consumable purchase
3. In RevenueCat dashboard, add the App Store credentials
4. Link the product to RevenueCat

#### Android (Google Play Console)
1. In Google Play Console, create an in-app product with ID: `full_access_unlock`
2. Make it a one-time purchase
3. In RevenueCat dashboard, add the Google Play credentials
4. Link the product to RevenueCat

### 3. Create Entitlement

1. In RevenueCat dashboard, go to Entitlements
2. Create an entitlement called `full_access`
3. Attach the `full_access_unlock` product to this entitlement

### 4. Get API Keys

1. In RevenueCat dashboard, go to API Keys
2. Copy the iOS/macOS API key (public key)
3. Copy the Android API key (public key)

### 5. Configure the App

Set the API keys as environment variables or build arguments:

#### For iOS/macOS:
```bash
flutter build ios --dart-define=REVENUECAT_IOS_API_KEY=your_ios_api_key_here
```

#### For Android:
```bash
flutter build apk --dart-define=REVENUECAT_ANDROID_API_KEY=your_android_api_key_here
```

#### For all platforms (example):
```bash
flutter build ios --dart-define=REVENUECAT_IOS_API_KEY=appl_xxxxx
flutter build appbundle --dart-define=REVENUECAT_ANDROID_API_KEY=goog_xxxxx
flutter build macos --dart-define=REVENUECAT_IOS_API_KEY=appl_xxxxx
```

## Offering Configuration

In RevenueCat dashboard, create an offering with:
- Package type: Lifetime
- Product: `full_access_unlock`

This allows users to purchase lifetime access to all features.

## Testing

### Test on iOS Simulator/Device
1. Use a sandbox Apple ID for testing
2. Build with the RevenueCat iOS API key
3. Test purchase and restore flows

### Test on Android Emulator/Device
1. Use a test Google account for testing
2. Build with the RevenueCat Android API key
3. Test purchase and restore flows

### Test on macOS
1. Use a sandbox Apple ID for testing
2. Build with the RevenueCat iOS API key (same as iOS)
3. Test purchase and restore flows

## Migration from Old System

The new RevenueCat integration maintains backward compatibility:
- Existing users who purchased before the RevenueCat integration will still have access
- The system checks for legacy purchases based on version history
- Trial period logic remains the same

## Code Structure

- `lib/utils/iap/revenuecat_service.dart` - RevenueCat service wrapper
- `lib/utils/iap/iap_manager.dart` - Unified IAP manager (uses RevenueCat for iOS/Android/macOS)
- `lib/utils/iap/windows_iap_service.dart` - Windows IAP (unchanged)

## Debugging

Enable debug logs by running in debug mode. RevenueCat logs will appear with prefix:
```
[Purchases] - DEBUG: ...
```

## Benefits of RevenueCat

1. **Server-side validation**: No client-side receipt validation needed
2. **Cross-platform**: Unified API for iOS, Android, macOS
3. **Analytics**: Track revenue, conversions, and user behavior
4. **Restore purchases**: Automatic restore across devices
5. **Subscription management**: Future-proof for subscription products
6. **A/B testing**: Test different pricing strategies

## Support

For RevenueCat-specific issues:
- Documentation: https://docs.revenuecat.com/
- Community: https://community.revenuecat.com/

For BikeControl IAP issues:
- Check the RevenueCat dashboard for purchase events
- Verify API keys are correctly set
- Check app logs for RevenueCat debug messages
