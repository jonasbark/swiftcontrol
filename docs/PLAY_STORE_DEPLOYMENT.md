# Play Store Deployment Setup

This document explains how to set up automated deployment to Google Play Store via GitHub Actions.

## Prerequisites

1. **Google Play Console Account**: You need a Google Play Console developer account
2. **Service Account**: Create a service account with Play Console API access
3. **App Published**: The app must be already published to Google Play Store

## Setup Instructions

### 1. Create Service Account

1. Go to the [Google Cloud Console](https://console.cloud.google.com/)
2. Create a new project or select existing project
3. Enable the Google Play Android Developer API
4. Go to IAM & Admin → Service Accounts
5. Create a new service account with a descriptive name
6. Download the JSON key file

### 2. Configure Play Console Access

1. Go to [Google Play Console](https://play.google.com/console/)
2. Go to Setup → API access
3. Link your Google Cloud project (if not already linked)
4. Grant access to your service account:
   - Go to Users and permissions
   - Invite the service account email
   - Grant "Release manager" role or appropriate permissions

### 3. GitHub Secrets Setup

Add the following secret to your GitHub repository:

- `GOOGLE_PLAY_SERVICE_ACCOUNT_JSON`: The entire content of the service account JSON file

### 4. Release Notes

The workflow uses release notes from the `metadata/android/en-US/changelogs/` directory.

Create a file named with your version code (e.g., `242.txt` for version 2.4.0+2) containing the release notes for that version.

## Workflow Behavior

- The Play Store upload only runs on pushes to the `main` branch
- It uploads the AAB file to the production track
- It automatically sets the release status to "completed" (100% rollout)
- It uses release notes from the changelogs directory

## Manual Override

If you need to upload manually or change settings, you can:

1. Disable the automatic upload by removing the Play Store step
2. Use the Google Play Console web interface
3. Use the `fastlane` tool for more advanced deployment scenarios

## Troubleshooting

- **Permission errors**: Ensure the service account has proper permissions in Play Console
- **API not enabled**: Make sure Google Play Android Developer API is enabled in Google Cloud Console
- **Version conflicts**: Ensure the version code in pubspec.yaml is higher than the current live version
- **Missing changelog**: Create a changelog file for the current version code