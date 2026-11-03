#!/bin/bash
set -euo pipefail
cd "${CM_BUILD_DIR:?Codemagic workspace is required}"
if ! command -v xcodegen >/dev/null 2>&1; then
  HOMEBREW_NO_AUTO_UPDATE=1 brew install xcodegen
fi
python3 -m venv .ci-venv
.ci-venv/bin/python -m pip install --disable-pip-version-check -r scripts/requirements-dev.txt
if [ "${SONO_INSTALL_SIGNING_TOOLS:-0}" = "1" ]; then
  .ci-venv/bin/python -m pip install --disable-pip-version-check -r scripts/ci/requirements.txt
fi
printf 'SONO_PYTHON=%s/.ci-venv/bin/python\n' "$CM_BUILD_DIR" >> "${CM_ENV:?Codemagic environment file is required}"
printf 'PATH=%s/.ci-venv/bin:%s\n' "$CM_BUILD_DIR" "$PATH" >> "$CM_ENV"
xcodebuild -version
swift --version
xcodegen --version
mkdir -p build/logs build/test-results
