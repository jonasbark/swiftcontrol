#!/bin/bash

# Build script for BikeControl with RevenueCat API keys
# This script demonstrates how to build the app with the required environment variables
#
# IMPORTANT: DO NOT commit actual API keys to version control!
# Set them as environment variables instead:
#   export REVENUECAT_IOS_API_KEY="appl_xxxxxxxxxxxxx"
#   export REVENUECAT_ANDROID_API_KEY="goog_xxxxxxxxxxxxx"
#
# Or create a local .env file (git-ignored) and source it:
#   source .env

# Check if API keys are set
if [ -z "$REVENUECAT_IOS_API_KEY" ]; then
    echo "WARNING: REVENUECAT_IOS_API_KEY is not set"
    echo "Set it with: export REVENUECAT_IOS_API_KEY=appl_xxxxxxxxxxxxx"
fi

if [ -z "$REVENUECAT_ANDROID_API_KEY" ]; then
    echo "WARNING: REVENUECAT_ANDROID_API_KEY is not set"
    echo "Set it with: export REVENUECAT_ANDROID_API_KEY=goog_xxxxxxxxxxxxx"
fi

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
