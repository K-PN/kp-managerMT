#!/bin/bash
set -euo pipefail
cd "${CM_BUILD_DIR:?Codemagic workspace is required}"
# Private keys are read by Codemagic CLI from secret environment variables.
# Never enable shell tracing or put key contents on the command line.
keychain initialize
app-store-connect fetch-signing-files "${BUNDLE_ID:?Bundle ID is required}" \
  --type IOS_APP_STORE --strict-match-identifier --create
keychain add-certificates
xcode-project use-profiles \
  --project SoNoAI.xcodeproj \
  --archive-method app-store \
  --export-options-plist build/release/export_options.plist \
  --custom-export-options='{"manageAppVersionAndBuildNumber":false}'
xcode-project build-ipa \
  --project SoNoAI.xcodeproj \
  --scheme SoNoAI \
  --config Release \
  --no-show-build-settings \
  --archive-directory build/ios/xcarchive \
  --ipa-directory build/ios/ipa \
  --export-options-plist build/release/export_options.plist \
  --archive-flags="-destination 'generic/platform=iOS'" \
  2>&1 | tee build/logs/archive.log
