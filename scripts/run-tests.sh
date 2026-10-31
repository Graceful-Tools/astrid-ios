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
source "$SCRIPT_DIR/lib/ios-destination.sh"
DESTINATION="$ASTRID_IOS_DESTINATION"

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
            echo "  --destination Set simulator destination (default: $ASTRID_IOS_DESTINATION)"
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

# Xcode 27 (on the runner since 2026-09-14) spends 600 seconds per test bundle trying to
# collect sysdiagnose-style diagnostics from the simulator and then gives up:
#   "Failure collecting diagnostics from simulator: Timed out after 600.0 seconds
#    while waiting for a response from the invoked process"
# It does that even when every test passed, and a UI run is two bundles, so twenty minutes
# of the CI step's thirty-minute budget went to a collection that never produced anything.
# That, not a hang in the app, is why `UI Tests (Simulator / Device)` had failed on every
# `main` run since 2026-09-15 while the monkey itself passed in five minutes.
#
# This turns off only the long-running sysdiagnose / log-archive collection. Test results,
# failure messages, screenshots and XCTAttachments (the monkey's journal and its final
# screenshot) are written to the .xcresult either way. Older xcodebuilds that predate the
# flag ignore it.
DIAGNOSTICS_FLAGS=(-collect-test-diagnostics never)

# Every run writes a result bundle, and the summary line reads its counts through
# xcresult-summary.sh. It used to `grep -c "passed"` the log, which counts LINES (AITD-524).
RESULTS_DIR="$PROJECT_DIR/test-results"
RESULTS_SUFFIX="${GITHUB_RUN_ID:-local}-${GITHUB_RUN_ATTEMPT:-1}-$(date +%s)"
mkdir -p "$RESULTS_DIR"
# A bundle per predeploy adds up; a week of them is plenty to look back through.
if [[ "${ASTRID_PRESERVE_TEST_RESULTS:-0}" != 1 ]]; then
    find "$RESULTS_DIR" -maxdepth 1 -name '*.xcresult' -mtime +7 -exec rm -rf {} + 2>/dev/null || true
fi
UNIT_RESULT="$RESULTS_DIR/unit-$RESULTS_SUFFIX.xcresult"

# Run unit tests
if [[ "$RUN_UNIT_TESTS" == "true" ]]; then
    echo -e "${BLUE}Running unit tests...${NC}"
    echo "  Destination: $DESTINATION"
    echo ""

    UNIT_LOG_DIR="${ASTRID_UNIT_TEST_LOG_DIR:-/tmp}"
    if [[ ! -d "$UNIT_LOG_DIR" || ! -w "$UNIT_LOG_DIR" ]]; then
        echo -e "${RED}✗ Unit-test log directory is not writable: $UNIT_LOG_DIR${NC}" >&2
        exit 1
    fi
    UNIT_LOG="$UNIT_LOG_DIR/unit_tests.log"

    set +e
    if [[ "$QUIET_MODE" == "true" ]]; then
        xcodebuild test \
            -scheme "Astrid App" \
            -destination "$DESTINATION" \
            -only-testing:"Astrid AppTests" \
            -resultBundlePath "$UNIT_RESULT" \
            -enableCodeCoverage YES \
            "${DIAGNOSTICS_FLAGS[@]}" \
            -quiet 2>&1 | tee "$UNIT_LOG"

        UNIT_EXIT=${PIPESTATUS[0]}
    else
        xcodebuild test \
            -scheme "Astrid App" \
            -destination "$DESTINATION" \
            -only-testing:"Astrid AppTests" \
            -resultBundlePath "$UNIT_RESULT" \
            -enableCodeCoverage YES \
            "${DIAGNOSTICS_FLAGS[@]}" 2>&1 | tee "$UNIT_LOG"

        UNIT_EXIT=${PIPESTATUS[0]}
    fi
    set -e

    if [[ $UNIT_EXIT -eq 0 ]]; then
        echo ""
        echo -e "${GREEN}✓ Unit tests passed ($("$PROJECT_DIR/scripts/xcresult-summary.sh" counts "$UNIT_RESULT"))${NC}"
        # Coverage by directory, against the committed floor (AITD-541). A drop fails the run.
        echo ""
        node "$PROJECT_DIR/scripts/coverage-report.mjs" ios "$UNIT_RESULT" \
            --floor "$PROJECT_DIR/scripts/coverage-floor.json" || exit 1
    else
        echo ""
        echo -e "${RED}✗ Unit tests failed${NC}"
        # Show failures
        grep -E "(failed|error:)" "$UNIT_LOG" | head -20 || true
        exit 1
    fi
    echo ""
fi

# Run UI tests
if [[ "$RUN_UI_TESTS" == "true" ]]; then
    # Hand the UI suite a session — for an account of this run's own (AITD-527). The mint,
    # plist and cleanup are shared with the Mac suite: scripts/lib/uitest-session.sh.
    SESSION_PLIST="$PROJECT_DIR/Astrid AppUITests/UITestSession.plist"
    source "$SCRIPT_DIR/lib/uitest-session.sh"
    trap cleanup_uitest_session EXIT

    echo -e "${BLUE}Running UI tests...${NC}"
    echo "  Destination: $DESTINATION"
    echo "  (This may take a few minutes)"
    echo ""

    write_uitest_session
    echo ""

    UI_MONKEY_RESULT="$RESULTS_DIR/ui-monkey-$RESULTS_SUFFIX.xcresult"
    UI_FUNCTIONAL_RESULT="$RESULTS_DIR/ui-functional-$RESULTS_SUFFIX.xcresult"
    : > /tmp/ui_monkey_tests.log
    : > /tmp/ui_functional_tests.log

    run_ui_batch() {
        local log_path="$1"
        local result_path="$2"
        shift 2

        xcodebuild test \
            -scheme "Astrid App" \
            -destination "$DESTINATION" \
            -resultBundlePath "$result_path" \
            "${DIAGNOSTICS_FLAGS[@]}" \
            "$@" \
            $QUIET_FLAG 2>&1 | tee "$log_path"
        return "${PIPESTATUS[0]}"
    }

    set +e
    # ParityTourUITests is a screenshot tool, not a test: it runs on its own -only-testing
    # invocation (see its header) and would only add a skip here (AITD-525).
    # Serial, not parallel clones: every clone of one run signs in to the SAME account, so two
    # of them ticked "the first open row" at once and testCompleteTask failed on a row its
    # neighbour had already completed (AITD-525). The account is per RUN since AITD-527, not
    # per clone, so this stays serial until a mint per clone exists.
    run_ui_batch \
        /tmp/ui_functional_tests.log \
        "$UI_FUNCTIONAL_RESULT" \
        -only-testing:"Astrid AppUITests" \
        -skip-testing:"Astrid AppUITests/MonkeyUITests" \
        -skip-testing:"Astrid AppUITests/ParityTourUITests" \
        -parallel-testing-enabled NO
    UI_EXIT=$?

    # The monkey runs AFTER the functional suite and does not gate it (AITD-530). It used to run
    # first and block it: one slow action on a loaded runner — a hang threshold measuring the
    # runner, not the app — kept every journey test from running, which is how the UI job was red
    # from 2026-10-15. It still runs alone (competing clones make false hangs) and its result is
    # still reported; it just cannot fail the gate.
    run_ui_batch \
        /tmp/ui_monkey_tests.log \
        "$UI_MONKEY_RESULT" \
        -only-testing:"Astrid AppUITests/MonkeyUITests" \
        -parallel-testing-enabled NO
    MONKEY_EXIT=$?
    cat /tmp/ui_monkey_tests.log /tmp/ui_functional_tests.log 2>/dev/null > /tmp/ui_tests.log
    set -e

    if [[ $MONKEY_EXIT -ne 0 ]]; then
        echo ""
        echo -e "${YELLOW}⚠ Monkey did not pass (non-blocking, AITD-530):${NC}"
        "$PROJECT_DIR/scripts/xcresult-summary.sh" failures "$UI_MONKEY_RESULT" | head -10 || true
    fi

    if [[ $UI_EXIT -eq 0 ]]; then
        echo ""
        echo -e "${GREEN}✓ UI tests passed ($("$PROJECT_DIR/scripts/xcresult-summary.sh" counts "$UI_MONKEY_RESULT" "$UI_FUNCTIONAL_RESULT"))${NC}"
    else
        echo ""
        echo -e "${RED}✗ UI tests failed${NC}"
        "$PROJECT_DIR/scripts/xcresult-summary.sh" failures "$UI_MONKEY_RESULT" "$UI_FUNCTIONAL_RESULT" \
            | tee "$RESULTS_DIR/ui-failures.txt" || true
        grep -E "(failed|error:)" /tmp/ui_tests.log | head -20 || true
        exit 1
    fi
    echo ""
fi

echo -e "${GREEN}=== All tests passed! ===${NC}"
