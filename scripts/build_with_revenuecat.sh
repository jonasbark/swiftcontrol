#!/bin/bash

# Build script example for BikeControl with RevenueCat API keys
# This script demonstrates how to build the app with the required environment variables

# Set your RevenueCat API keys here
# Get these from the RevenueCat dashboard: https://app.revenuecat.com/
REVENUECAT_IOS_API_KEY="appl_xxxxxxxxxxxxx"  # Replace with your actual iOS API key
REVENUECAT_ANDROID_API_KEY="goog_xxxxxxxxxxxxx"  # Replace with your actual Android API key

# Build for iOS
build_ios() {
    echo "Building for iOS..."
    flutter build ios \
        --dart-define=REVENUECAT_IOS_API_KEY=$REVENUECAT_IOS_API_KEY \
        --release
}

# Build for Android (APK)
build_android_apk() {
    echo "Building Android APK..."
    flutter build apk \
        --dart-define=REVENUECAT_ANDROID_API_KEY=$REVENUECAT_ANDROID_API_KEY \
        --release
}

# Build for Android (App Bundle)
build_android_appbundle() {
    echo "Building Android App Bundle..."
    flutter build appbundle \
        --dart-define=REVENUECAT_ANDROID_API_KEY=$REVENUECAT_ANDROID_API_KEY \
        --release
}

# Build for macOS
build_macos() {
    echo "Building for macOS..."
    flutter build macos \
        --dart-define=REVENUECAT_IOS_API_KEY=$REVENUECAT_IOS_API_KEY \
        --release
}

# Show usage
show_usage() {
    echo "Usage: $0 [platform]"
    echo "Platforms:"
    echo "  ios        - Build for iOS"
    echo "  android    - Build Android APK"
    echo "  appbundle  - Build Android App Bundle"
    echo "  macos      - Build for macOS"
    echo "  all        - Build for all platforms"
}

# Main script
case "$1" in
    ios)
        build_ios
        ;;
    android)
        build_android_apk
        ;;
    appbundle)
        build_android_appbundle
        ;;
    macos)
        build_macos
        ;;
    all)
        build_ios
        build_android_appbundle
        build_macos
        ;;
    *)
        show_usage
        exit 1
        ;;
esac

echo "Build completed!"
