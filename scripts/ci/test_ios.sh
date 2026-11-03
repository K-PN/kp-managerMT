#!/bin/bash
set -euo pipefail
cd "${CM_BUILD_DIR:?Codemagic workspace is required}"
mkdir -p build/logs build/test-results
SIMULATOR_ID=$("${SONO_PYTHON:?Python environment is required}" scripts/ci/pipeline.py simulator)
xcrun simctl boot "$SIMULATOR_ID" 2>/dev/null || true
xcrun simctl bootstatus "$SIMULATOR_ID" -b
xcodebuild test \
  -project SoNoAI.xcodeproj \
  -scheme SoNoAI \
  -destination "platform=iOS Simulator,id=$SIMULATOR_ID" \
  -derivedDataPath DerivedData \
  -resultBundlePath build/test-results/SoNoAppTests.xcresult \
  CODE_SIGNING_ALLOWED=NO 2>&1 | tee build/logs/xcode-test.log
