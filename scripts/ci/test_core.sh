#!/bin/bash
set -euo pipefail
cd "${CM_BUILD_DIR:?Codemagic workspace is required}"
mkdir -p build/logs build/test-results
swift test --xunit-output build/test-results/core.xml 2>&1 | tee build/logs/swift-test.log
