#!/bin/bash

set -euo pipefail

DERIVED_DATA_PATH="/tmp/astrid-mac-dd"
COMMON_ARGS=(
    -scheme "Astrid Mac"
    -destination "platform=macOS,arch=arm64"
    -derivedDataPath "${DERIVED_DATA_PATH}"
    # Instrumentation is decided at BUILD time: on test-without-building alone, the run finds no
    # coverage archive.
    -enableCodeCoverage YES
    -quiet
)

# Coverage (AITD-541): every run measures it, and a SANDBOXED Mac app writes no profile data —
# `xccov` then fails with "Failed to load coverage archive". So the app is built unsandboxed and
# ad-hoc signed, locally as in CI, which also lets the source-contract tests read the checkout.
# The one assertion that needs the sandboxed signature is skipped here and stays covered by the
# Xcode Cloud Mac lane.
SIGNING_ARGS=(
    CODE_SIGN_IDENTITY=-
    CODE_SIGNING_ALLOWED=YES
    CODE_SIGN_ENTITLEMENTS=
    ENABLE_APP_SANDBOX=NO
    ENABLE_HARDENED_RUNTIME=NO
)
TEST_ARGS=(
    -skip-testing:"Astrid MacTests/MacSignInOptionsTests/testItCanReadThisBuildsSignature"
)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
RESULT="$PROJECT_DIR/test-results/mac-unit-${GITHUB_RUN_ID:-local}-$(date +%s).xcresult"
mkdir -p "$PROJECT_DIR/test-results"

xcodebuild build-for-testing "${COMMON_ARGS[@]}" "${SIGNING_ARGS[@]}"
xcodebuild test-without-building \
    "${COMMON_ARGS[@]}" \
    -only-testing:"Astrid MacTests" \
    -parallel-testing-enabled NO \
    -resultBundlePath "$RESULT" \
    ${TEST_ARGS[@]+"${TEST_ARGS[@]}"} \
    "${SIGNING_ARGS[@]}"

echo "Mac unit tests: $("$SCRIPT_DIR/xcresult-summary.sh" counts "$RESULT")"
node "$SCRIPT_DIR/coverage-report.mjs" mac "$RESULT" --floor "$SCRIPT_DIR/coverage-floor.json"
