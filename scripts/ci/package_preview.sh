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
# test_ios.sh already preserves attachments on exit, including successful tests.
# Exporting into that directory again fails when Xcode writes manifest.json.
if [ ! -f build/screenshots/manifest.json ]; then
  xcrun xcresulttool export attachments \
    --path build/test-results/SoNoAppTests.xcresult \
    --output-path build/screenshots
fi
"${SONO_PYTHON:?Python environment is required}" -c '
import json
from pathlib import Path
folder = Path("build/screenshots")
json.loads((folder / "manifest.json").read_text(encoding="utf-8"))
if not any(folder.rglob("*.png")):
    raise SystemExit("No UI screenshots were exported.")
'
printf '%s\n' 'Packaged the real Simulator app and exported UI test screenshot attachments.'
