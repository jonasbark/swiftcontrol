# F-Droid Release Documentation

This document explains how to release SwiftControl on F-Droid, the free and open source Android app repository.

## Overview

F-Droid builds apps from source code and distributes them without any proprietary components. SwiftControl has been prepared for F-Droid compatibility with the following changes:

## Files Added for F-Droid

### 1. Fastlane Metadata (`fastlane/metadata/android/en-US/`)
- `title.txt` - App title
- `short_description.txt` - Brief description (max 80 chars)
- `full_description.txt` - Detailed app description
- `changelogs/` - Version-specific changelogs

### 2. F-Droid Metadata (`metadata/en-US.yml`)
This file contains all the information F-Droid needs to build and publish the app:
- App metadata (name, description, categories)
- Build instructions
- Dependencies and requirements
- Repository information

### 3. Build Configuration Changes
Modified `android/app/build.gradle.kts` to:
- Handle missing keystore.properties gracefully (F-Droid doesn't use custom signing)
- Support reproducible builds without proprietary signing configurations

## F-Droid Submission Process

### Step 1: Prepare the Submission
The GitHub Actions workflow automatically creates F-Droid submission files in each release under `SwiftControl.fdroid-submission.zip`.

### Step 2: Submit to F-Droid
1. Fork the F-Droid Data repository: https://gitlab.com/fdroid/fdroiddata
2. Extract the submission files from the release
3. Copy `en-US.yml` to `metadata/de.jonasbark.swift_play.yml` in the F-Droid Data repository
4. Optionally copy fastlane metadata to provide richer app store information
5. Submit a merge request to the F-Droid Data repository

### Step 3: F-Droid Review Process
- F-Droid maintainers will review the submission
- They will verify the app builds correctly from source
- They will check for any policy violations
- Once approved, the app will be available in the F-Droid repository

## Build Requirements

### Dependencies
All dependencies are open source and compatible with F-Droid:
- Flutter SDK (stable channel)
- Standard Android SDK
- All Pub.dev packages used are FOSS-compatible

### Build Process
- Uses standard Flutter build process: `flutter build apk --release`
- No proprietary SDKs or services
- No custom signing (F-Droid handles signing)
- Reproducible builds supported

## Maintenance

### Updating F-Droid Releases
1. Update the version in `pubspec.yaml`
2. Add changelog entry to `fastlane/metadata/android/en-US/changelogs/[versioncode].txt`
3. Update `metadata/en-US.yml` with new version information
4. Create a new release - GitHub Actions will automatically prepare F-Droid submission files
5. Submit update to F-Droid Data repository

### Version Code Mapping
F-Droid uses integer version codes. Current mapping:
- Version 2.1.0 = Version Code 210
- Follow semantic versioning: MAJOR.MINOR.PATCH = MAJORMINORPATCH

## Troubleshooting

### Common Issues
1. **Build failures**: Ensure all dependencies are available in F-Droid's build environment
2. **Signing issues**: F-Droid handles its own signing, custom keystore configurations are ignored
3. **Reproducible builds**: All build steps must be deterministic

### Testing F-Droid Builds Locally
You can test F-Droid compatibility by building without keystore.properties:
```bash
cd android
rm keystore.properties  # temporarily remove
flutter build apk --release
```

## Resources

- [F-Droid Docs](https://f-droid.org/docs/)
- [F-Droid Data Repository](https://gitlab.com/fdroid/fdroiddata)
- [F-Droid Build Metadata Reference](https://f-droid.org/docs/Build_Metadata_Reference/)
- [Fastlane Metadata for F-Droid](https://f-droid.org/docs/All_About_Descriptions_Graphics_and_Screenshots/)