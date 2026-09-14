#!/bin/bash

# Predeploy Script for Astrid iOS
# Runs all validation checks before deployment

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
source "$SCRIPT_DIR/lib/ios-destination.sh"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Default options
RUN_UI_TESTS=false
SKIP_BUILD=false
QUICK_MODE=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --full)
            RUN_UI_TESTS=true
            shift
            ;;
        --quick)
            QUICK_MODE=true
            shift
            ;;
        --skip-build)
            SKIP_BUILD=true
            shift
            ;;
        --help)
            echo "Astrid iOS Predeploy Script"
            echo ""
            echo "Usage: $0 [options]"
            echo ""
            echo "Options:"
            echo "  --full        Run full checks including UI tests"
            echo "  --quick       Run quick checks only (skip tests)"
            echo "  --skip-build  Skip the build verification step"
            echo "  --help        Show this help"
            echo ""
            echo "Default behavior:"
            echo "  - Check neither target's MARKETING_VERSION is already released (skips offline)"
            echo "  - Check localizations"
            echo "  - Check brand literals"
            echo "  - Audit partner brand profiles"
            echo "  - Run unit tests"
            echo "  - Verify build compiles"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

cd "$PROJECT_DIR"

echo ""
echo -e "${CYAN}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║           Astrid iOS Predeploy Checks                      ║${NC}"
echo -e "${CYAN}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""

STEP=0
TOTAL_STEPS=6
if [[ "$RUN_UI_TESTS" == "true" ]]; then
    TOTAL_STEPS=8
fi
if [[ "$QUICK_MODE" == "true" ]]; then
    TOTAL_STEPS=4
fi

# Print the numbered banner for the next step.
step() {
    STEP=$((STEP + 1))
    echo -e "${BLUE}[$STEP/$TOTAL_STEPS] $1${NC}"
    echo ""
}

# Run a gate script; exit with the given failure message if it fails.
gate() {
    local ok="$1" fail="$2"; shift 2
    if "$@"; then
        echo -e "${GREEN}✓ $ok${NC}"
    else
        echo -e "${RED}✗ $fail${NC}"
        exit 1
    fi
    echo ""
}

# The simulator build. One definition — the quick-mode path used to carry its own copy.
build_ios() {
    set +e
    xcodebuild build \
        -scheme "Astrid App" \
        -destination "$ASTRID_IOS_DESTINATION" \
        -quiet 2>&1
    local build_exit=$?
    set -e
    [[ $build_exit -eq 0 ]]
}

# Step 1: App Store version state (AITD-396)
# First, in every mode, because it is the cheapest check and the one that used to cost the most
# to miss: a MARKETING_VERSION that App Store Connect has already released makes Xcode Cloud fail
# nine minutes in with a bare "PrepareBuildForAppStoreConnect failed" and nothing in the logs.
# Both targets — they version independently under one app record, and the failure mode is one
# of them drifting. Fails ONLY on a positive collision: no key or no network prints a "skipped"
# line and passes, so the gate still runs offline. In quick mode too: that is the mode people
# reach for in a hurry, which is exactly when this gets missed.
step "Checking App Store version state..."
gate "Version check passed" "Version check failed — a released MARKETING_VERSION cannot take new builds" \
    "$SCRIPT_DIR/check-version.sh" all

# Step 2: Localization checks
step "Checking localizations..."
gate "Localization checks passed" "Localization checks failed" "$SCRIPT_DIR/check-localizations.sh"

# Step 3: Brand-literal checks (whitelabel — task 97208a72)
# Its own gate, not folded into the unit tests, so a whitelabel regression is reported
# as itself rather than as one failure among 1200. A brand literal is invisible on an
# Astrid build and only surfaces on a partner's, where nobody is watching.
step "Checking brand literals..."
gate "Brand checks passed" "Brand checks failed" "$SCRIPT_DIR/check-brand.sh"

# Step 4: Build verification (unless skipped). Quick mode builds too, after the cheap checks.
if [[ "$SKIP_BUILD" != "true" ]]; then
    step "Verifying build compiles..."
    gate "Build verification passed" "Build failed" build_ios
fi

# Step 5: Partner brand audit (unless quick mode)
# Its own gate for the same reason as the web's brand matrix: a whitelabel regression
# should be reported as itself. This is the ONLY gate that can see one — on an Astrid
# build every brand assertion is vacuous, because a reverted literal still compares
# equal to the configured value. Task 97208a72.
if [[ "$QUICK_MODE" != "true" ]]; then
    step "Auditing partner brand profiles..."
    gate "Brand audit passed" "Brand audit failed" "$SCRIPT_DIR/check-brands.sh"
fi

# Step 6: Unit tests (unless quick mode)
if [[ "$QUICK_MODE" != "true" ]]; then
    step "Running unit tests..."
    gate "Unit tests passed" "Unit tests failed" "$SCRIPT_DIR/run-tests.sh"
    # The version check above is a shell script; this is its test (AITD-396). Here rather than
    # in run-tests.sh because it is not an Xcode test, and it takes well under a second.
    gate "Script tests passed" "Script tests failed" "$SCRIPT_DIR/test-check-version.sh"
fi

# Step 7: UI tests (only with --full)
if [[ "$RUN_UI_TESTS" == "true" ]]; then
    step "Running UI tests..."
    gate "UI tests passed" "UI tests failed" "$SCRIPT_DIR/run-tests.sh" --ui --no-unit
fi

# Step 8: Mac tests (only with --full)
if [[ "$RUN_UI_TESTS" == "true" ]]; then
    step "Running Mac tests..."
    gate "Mac tests passed" "Mac tests failed" "$SCRIPT_DIR/run-mac-tests.sh"
fi

# Summary
echo ""
echo -e "${CYAN}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║                                                            ║${NC}"
echo -e "${CYAN}║  ${GREEN}✓ All predeploy checks passed!${CYAN}                           ║${NC}"
echo -e "${CYAN}║                                                            ║${NC}"
echo -e "${CYAN}║  Ready to push to main for Xcode Cloud deployment.        ║${NC}"
echo -e "${CYAN}║                                                            ║${NC}"
echo -e "${CYAN}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""
