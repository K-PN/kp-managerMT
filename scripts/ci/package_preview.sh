#!/bin/bash
set -euo pipefail
cd "${CM_BUILD_DIR:?Codemagic workspace is required}"
APP_PATH="DerivedData/Build/Products/Debug-iphonesimulator/SoNoAI.app"
if [ ! -d "$APP_PATH" ]; then
  printf '%s\n' 'No Simulator app was produced. Build/test must succeed first.' >&2
  exit 1
fi
mkdir -p build/preview build/screenshots
ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" build/preview/SoNoAI-simulator.zip
xcrun xcresulttool export attachments \
  --path build/test-results/SoNoAppTests.xcresult \
  --output-path build/screenshots
printf '%s\n' 'Packaged the real Simulator app and exported UI test screenshot attachments.'
