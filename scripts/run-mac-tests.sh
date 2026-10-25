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
mkdir -p "$PROJECT_DIR/test-results"

# --ui: the Mac UI suite, signed in with a per-run account (AITD-529). Until this existed the 12
# non-monkey Mac UI tests were launched by nothing, and they could not have been signed in if
# they were. The monkey keeps its own script (`monkey-test.sh mac`) and is skipped here.
if [[ "${1:-}" == "--ui" ]]; then
    # Developer mode off: every runner attach needs an interactive admin authentication, which
    # a non-interactive run cannot answer — it surfaces as LocalAuthentication Code=-4.
    if ! DevToolsSecurity -status 2>/dev/null | grep -q enabled; then
        echo "RESULT: FAILED — developer mode is off, so the UI-test runner cannot start."
        echo "  Fix (needs your password, once per machine): sudo DevToolsSecurity -enable"
        exit 1
    fi
    # A locked screen shields every window: the app launches but never reaches the foreground,
    # and XCUITest fails launch() with "Failed to activate application" (AITD-530).
    if ioreg -n Root -d1 -a 2>/dev/null | plutil -extract IOConsoleUsers xml1 -o - - 2>/dev/null \
         | grep -A1 CGSSessionScreenIsLocked | grep -q "<true/>"; then
        echo "RESULT: FAILED — the screen is locked, so the Mac app cannot reach the foreground. Unlock it and re-run."
        exit 3
    fi

    SESSION_PLIST="$PROJECT_DIR/Astrid MacUITests/UITestSession.plist"
    source "$SCRIPT_DIR/lib/uitest-session.sh"
    trap cleanup_uitest_session EXIT
    write_uitest_session

    UI_RESULT="$PROJECT_DIR/test-results/mac-ui-${GITHUB_RUN_ID:-local}-$(date +%s).xcresult"
    # Built, then given its own bundle id before anything launches it (AITD-529): under the
    # shipping id the app opens the installed Astrid's container and reads the owner's saved
    # settings. See lib/mac-uitest-identity.sh. One test at a time — the suite shares one screen.
    UI_ARGS=(
        -scheme "Astrid Mac"
        -destination "platform=macOS,arch=arm64"
        -derivedDataPath /tmp/astrid-mac-ui-dd
        -quiet
    )
    xcodebuild build-for-testing "${UI_ARGS[@]}"
    "$SCRIPT_DIR/lib/mac-uitest-identity.sh" /tmp/astrid-mac-ui-dd/Build/Products/Debug/Astrid.app
    set +e
    xcodebuild test-without-building "${UI_ARGS[@]}" \
        -only-testing:"Astrid MacUITests" \
        -skip-testing:"Astrid MacUITests/MacMonkeyUITests" \
        -parallel-testing-enabled NO \
        -collect-test-diagnostics never \
        -resultBundlePath "$UI_RESULT"
    UI_EXIT=$?
    set -e
    echo "Mac UI tests: $("$SCRIPT_DIR/xcresult-summary.sh" counts "$UI_RESULT")"
    exit $UI_EXIT
fi

RESULT="$PROJECT_DIR/test-results/mac-unit-${GITHUB_RUN_ID:-local}-$(date +%s).xcresult"

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
