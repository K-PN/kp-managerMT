#!/bin/bash
set -euo pipefail
cd "${CM_BUILD_DIR:?Codemagic workspace is required}"
# Codemagic's ios_signing imports the existing distribution certificate and
# matching profile into the build keychain. No new certificates are created.
# Never enable shell tracing or put key contents on the command line.
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
