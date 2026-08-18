#!/bin/bash

# Test Runner Script for Astrid iOS
# Runs unit tests and optionally UI tests

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default options
RUN_UNIT_TESTS=true
RUN_UI_TESTS=false
QUIET_MODE=true
DESTINATION="platform=iOS Simulator,name=iPhone 17"

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --ui)
            RUN_UI_TESTS=true
            shift
            ;;
        --no-unit)
            RUN_UNIT_TESTS=false
            shift
            ;;
        --verbose)
            QUIET_MODE=false
            shift
            ;;
        --destination)
            DESTINATION="$2"
            shift 2
            ;;
        --help)
            echo "Usage: $0 [options]"
            echo ""
            echo "Options:"
            echo "  --ui          Also run UI tests (slower)"
            echo "  --no-unit     Skip unit tests"
            echo "  --verbose     Show full xcodebuild output"
            echo "  --destination Set simulator destination (default: iPhone 17)"
            echo "  --help        Show this help"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

cd "$PROJECT_DIR"

echo -e "${BLUE}=== Astrid iOS Test Runner ===${NC}"
echo ""

QUIET_FLAG=""
if [[ "$QUIET_MODE" == "true" ]]; then
    QUIET_FLAG="-quiet"
fi

# Run unit tests
if [[ "$RUN_UNIT_TESTS" == "true" ]]; then
    echo -e "${BLUE}Running unit tests...${NC}"
    echo "  Destination: $DESTINATION"
    echo ""

    set +e
    if [[ "$QUIET_MODE" == "true" ]]; then
        xcodebuild test \
            -scheme "Astrid App" \
            -destination "$DESTINATION" \
            -only-testing:"Astrid AppTests" \
            -quiet 2>&1 | tee /tmp/unit_tests.log

        UNIT_EXIT=${PIPESTATUS[0]}
    else
        xcodebuild test \
            -scheme "Astrid App" \
            -destination "$DESTINATION" \
            -only-testing:"Astrid AppTests" 2>&1 | tee /tmp/unit_tests.log

        UNIT_EXIT=${PIPESTATUS[0]}
    fi
    set -e

    if [[ $UNIT_EXIT -eq 0 ]]; then
        # Count passed tests
        PASSED=$(grep -c "passed" /tmp/unit_tests.log 2>/dev/null || echo 0)
        SKIPPED=$(grep -c "skipped" /tmp/unit_tests.log 2>/dev/null || echo 0)
        echo ""
        echo -e "${GREEN}✓ Unit tests passed ($PASSED passed, $SKIPPED skipped)${NC}"
    else
        echo ""
        echo -e "${RED}✗ Unit tests failed${NC}"
        # Show failures
        grep -E "(failed|error:)" /tmp/unit_tests.log | head -20 || true
        exit 1
    fi
    echo ""
fi

# Hand the UI suite a session for the dedicated uitest@astrid.cc account.
#
# Not an environment variable: xcodebuild forwards neither the plain variable nor the
# TEST_RUNNER_-prefixed build setting to the xctrunner process (measured 2026-08-16), so the
# first attempt at this silently injected nothing and the whole suite ran signed out while
# reporting success. A file inside the test bundle does arrive. See UITestLaunch.swift.
#
# The file is gitignored and rewritten every run — a NextAuth session expires after 30 days,
# and a committed token would fail in a way indistinguishable from the skip it replaced.
SESSION_PLIST="$PROJECT_DIR/Astrid AppUITests/UITestSession.plist"

write_uitest_session() {
    local cookie="${ASTRID_UITEST_COOKIE:-}"

    if [[ -z "$cookie" && -d "$PROJECT_DIR/../astrid-web" ]]; then
        echo -e "${BLUE}Minting a session for uitest@astrid.cc...${NC}"
        cookie="$(cd "$PROJECT_DIR/../astrid-web" && npx tsx scripts/uitest-account.ts --cookie 2>/dev/null | tail -1)" || cookie=""
    fi

    if [[ -z "$cookie" ]]; then
        # A hard stop, not a warning. Signed out, every test that needs an account skips
        # itself and the run still reports "✓ UI tests passed (28 passed, 36 skipped)" —
        # green while asserting nothing, which is the exact failure this account exists to
        # end. It went unnoticed for a day because the warning scrolled past in a ten-minute
        # run and the summary said passed (task b86c97c5).
        echo -e "${RED}✗ No test-account session available — refusing to run the UI suite.${NC}"
        echo "  Signed out, every test that needs an account skips and the run reports green."
        echo "  Mint one: cd ../astrid-web && npx tsx scripts/uitest-account.ts --cookie"
        echo "  Or pass one: ASTRID_UITEST_COOKIE=... npm run test:ui"
        rm -f "$SESSION_PLIST"
        exit 1
    fi

    /usr/libexec/PlistBuddy -c "Clear dict" -c "Add :sessionCookie string $cookie" \
        "$SESSION_PLIST" >/dev/null 2>&1 || {
        rm -f "$SESSION_PLIST"
        /usr/libexec/PlistBuddy -c "Add :sessionCookie string $cookie" "$SESSION_PLIST" >/dev/null
    }
    echo -e "${GREEN}✓ Test-account session written (${#cookie} chars)${NC}"
}

# Never leave a live credential lying in the working tree.
cleanup_uitest_session() { rm -f "$SESSION_PLIST"; }
trap cleanup_uitest_session EXIT

# Run UI tests
if [[ "$RUN_UI_TESTS" == "true" ]]; then
    echo -e "${BLUE}Running UI tests...${NC}"
    echo "  Destination: $DESTINATION"
    echo "  (This may take a few minutes)"
    echo ""

    write_uitest_session
    echo ""

    set +e
    if [[ "$QUIET_MODE" == "true" ]]; then
        xcodebuild test \
            -scheme "Astrid App" \
            -destination "$DESTINATION" \
            -only-testing:"Astrid AppUITests" \
            -quiet 2>&1 | tee /tmp/ui_tests.log

        UI_EXIT=${PIPESTATUS[0]}
    else
        xcodebuild test \
            -scheme "Astrid App" \
            -destination "$DESTINATION" \
            -only-testing:"Astrid AppUITests" 2>&1 | tee /tmp/ui_tests.log

        UI_EXIT=${PIPESTATUS[0]}
    fi
    set -e

    if [[ $UI_EXIT -eq 0 ]]; then
        PASSED=$(grep -c "passed" /tmp/ui_tests.log 2>/dev/null || echo 0)
        SKIPPED=$(grep -c "skipped" /tmp/ui_tests.log 2>/dev/null || echo 0)
        echo ""
        echo -e "${GREEN}✓ UI tests passed ($PASSED passed, $SKIPPED skipped)${NC}"
    else
        echo ""
        echo -e "${RED}✗ UI tests failed${NC}"
        grep -E "(failed|error:)" /tmp/ui_tests.log | head -20 || true
        exit 1
    fi
    echo ""
fi

echo -e "${GREEN}=== All tests passed! ===${NC}"
