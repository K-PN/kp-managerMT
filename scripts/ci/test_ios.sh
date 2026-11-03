#!/bin/bash
set -euo pipefail
cd "${CM_BUILD_DIR:?Codemagic workspace is required}"
mkdir -p build/logs build/test-results
# Compile first so source/SDK errors are reported without waiting for first boot.
xcodebuild build-for-testing \
  -project SoNoAI.xcodeproj \
  -scheme SoNoAI \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath DerivedData \
  CODE_SIGNING_ALLOWED=NO 2>&1 | tee build/logs/xcode-build.log
SIMULATOR_ID=$("${SONO_PYTHON:?Python environment is required}" scripts/ci/pipeline.py simulator)
xcrun simctl boot "$SIMULATOR_ID" 2>/dev/null || true
"$SONO_PYTHON" -c 'import subprocess,sys; subprocess.run(["xcrun","simctl","bootstatus",sys.argv[1],"-b"],check=True,timeout=420)' "$SIMULATOR_ID"
xcodebuild test-without-building \
  -project SoNoAI.xcodeproj \
  -scheme SoNoAI \
  -destination "platform=iOS Simulator,id=$SIMULATOR_ID" \
  -derivedDataPath DerivedData \
  -resultBundlePath build/test-results/SoNoAppTests.xcresult \
  CODE_SIGNING_ALLOWED=NO 2>&1 | tee build/logs/xcode-test.log
