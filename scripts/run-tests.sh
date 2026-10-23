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
find "$RESULTS_DIR" -maxdepth 1 -name '*.xcresult' -mtime +7 -exec rm -rf {} + 2>/dev/null || true
UNIT_RESULT="$RESULTS_DIR/unit-$RESULTS_SUFFIX.xcresult"

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
            -resultBundlePath "$UNIT_RESULT" \
            "${DIAGNOSTICS_FLAGS[@]}" \
            -quiet 2>&1 | tee /tmp/unit_tests.log

        UNIT_EXIT=${PIPESTATUS[0]}
    else
        xcodebuild test \
            -scheme "Astrid App" \
            -destination "$DESTINATION" \
            -only-testing:"Astrid AppTests" \
            -resultBundlePath "$UNIT_RESULT" \
            "${DIAGNOSTICS_FLAGS[@]}" 2>&1 | tee /tmp/unit_tests.log

        UNIT_EXIT=${PIPESTATUS[0]}
    fi
    set -e

    if [[ $UNIT_EXIT -eq 0 ]]; then
        echo ""
        echo -e "${GREEN}✓ Unit tests passed ($("$PROJECT_DIR/scripts/xcresult-summary.sh" counts "$UNIT_RESULT"))${NC}"
    else
        echo ""
        echo -e "${RED}✗ Unit tests failed${NC}"
        # Show failures
        grep -E "(failed|error:)" /tmp/unit_tests.log | head -20 || true
        exit 1
    fi
    echo ""
fi

# Hand the UI suite a session — for an account of this run's own (AITD-527).
#
# Not an environment variable: xcodebuild forwards neither the plain variable nor the
# TEST_RUNNER_-prefixed build setting to the xctrunner process (measured 2026-08-16), so the
# first attempt at this silently injected nothing and the whole suite ran signed out while
# reporting success. A file inside the test bundle does arrive. See UITestLaunch.swift.
#
# The file is gitignored and rewritten every run — a NextAuth session expires after 30 days,
# and a committed token would fail in a way indistinguishable from the skip it replaced.
#
# **A run gets its own account.** Every runner used to mint the one shared uitest@astrid.cc, and
# each mint wipes and reseeds it — so a CI job minting mid-run deleted a local run's tasks
# under it. `uitest-account.ts --run <id>` (AWTD-1328) mints uitest+<id>@astrid.cc with its own
# lists and fixtures and prints one JSON document; the fixture ids go into the plist next to
# the cookie, so a test can name a task by id and check it on the server (UITestAPI). The
# EXIT trap deletes the account; a run killed before the trap fires is reaped by the next
# mint after 24 hours.
#
# ASTRID_UITEST_COOKIE still works, for the shared account, with no fixture ids.
# ASTRID_UITEST_BASE_URL points the run at another server (`-uiTestBaseURL`), e.g. staging.
SESSION_PLIST="$PROJECT_DIR/Astrid AppUITests/UITestSession.plist"
ASTRID_WEB_DIR="${ASTRID_WEB_DIR:-$PROJECT_DIR/../astrid-web}"
UITEST_RUN_ID=""

# A run id is 1-48 chars of [a-z0-9-], starts with a letter or digit, never ends in -owner.
uitest_run_id() {
    if [[ -n "${ASTRID_UITEST_RUN_ID:-}" ]]; then
        echo "$ASTRID_UITEST_RUN_ID"
    elif [[ -n "${GITHUB_RUN_ID:-}" ]]; then
        echo "gha-${GITHUB_RUN_ID}-${GITHUB_RUN_ATTEMPT:-1}"
    else
        echo "local-$$-$(date +%s)"
    fi
}

# tsx does not read .env.local on its own, and without it the mint dies on "NEXTAUTH_SECRET
# missing". CI has no .env.local (the secrets arrive as environment), and --env-file on a
# missing file is an error, so pass it only when the file is there.
uitest_account() {
    local env_flag=()
    [[ -f "$ASTRID_WEB_DIR/.env.local" ]] && env_flag=(--env-file=.env.local)
    (cd "$ASTRID_WEB_DIR" && npx tsx "${env_flag[@]}" scripts/uitest-account.ts "$@")
}

write_uitest_session() {
    local cookie="${ASTRID_UITEST_COOKIE:-}"
    local fixtures=""

    if [[ -z "$cookie" && -d "$ASTRID_WEB_DIR" ]]; then
        local run_id minted
        run_id="$(uitest_run_id)"
        echo -e "${BLUE}Minting a test account for run ${run_id}...${NC}"
        minted="$(uitest_account --run "$run_id" 2>/tmp/uitest_mint.log)" || minted=""
        if [[ -n "$minted" ]]; then
            UITEST_RUN_ID="$run_id"
            cookie="$(printf '%s' "$minted" | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{try{process.stdout.write(JSON.parse(s).cookie||"")}catch{}})')"
            fixtures="$(printf '%s' "$minted" | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{try{process.stdout.write(JSON.stringify(JSON.parse(s).fixtures||null))}catch{}})')"
        else
            tail -5 /tmp/uitest_mint.log >&2 || true
        fi
    fi

    if [[ -z "$cookie" ]]; then
        # A hard stop, not a warning. Signed out, every test that needs an account skips
        # itself and the run still reports "✓ UI tests passed (28 passed, 36 skipped)" —
        # green while asserting nothing, which is the exact failure this account exists to
        # end. It went unnoticed for a day because the warning scrolled past in a ten-minute
        # run and the summary said passed (task b86c97c5).
        echo -e "${RED}✗ No test-account session available — refusing to run the UI suite.${NC}"
        echo "  Signed out, every test that needs an account skips and the run reports green."
        echo "  Mint one: cd ../astrid-web && npx tsx scripts/uitest-account.ts --run <id>"
        echo "  Or pass one: ASTRID_UITEST_COOKIE=... npm run test:ui"
        rm -f "$SESSION_PLIST"
        exit 1
    fi

    # GitHub masks the cookie only once it has been told to.
    [[ "${GITHUB_ACTIONS:-}" == "true" ]] && echo "::add-mask::${cookie}"

    # Built as JSON and converted, because a fixtures document full of quotes and spaces does
    # not survive PlistBuddy's command parsing.
    local json_tmp
    json_tmp="$(mktemp -t uitest-session)"
    UITEST_COOKIE="$cookie" UITEST_FIXTURES="$fixtures" UITEST_RUN="$UITEST_RUN_ID" \
    UITEST_BASE_URL="${ASTRID_UITEST_BASE_URL:-}" node -e '
        const out = { sessionCookie: process.env.UITEST_COOKIE }
        if (process.env.UITEST_FIXTURES && process.env.UITEST_FIXTURES !== "null") out.fixtures = process.env.UITEST_FIXTURES
        if (process.env.UITEST_RUN) out.runId = process.env.UITEST_RUN
        if (process.env.UITEST_BASE_URL) out.baseURL = process.env.UITEST_BASE_URL
        process.stdout.write(JSON.stringify(out))' > "$json_tmp"
    plutil -convert xml1 -o "$SESSION_PLIST" "$json_tmp"
    rm -f "$json_tmp"

    if [[ -n "$UITEST_RUN_ID" ]]; then
        echo -e "${GREEN}✓ Test account for run ${UITEST_RUN_ID} written (cookie ${#cookie} chars, fixture ids included)${NC}"
    else
        echo -e "${GREEN}✓ Test-account session written (${#cookie} chars; shared account, no fixture ids)${NC}"
    fi
}

# Never leave a live credential lying in the working tree, nor a run's account on the server.
cleanup_uitest_session() {
    rm -f "$SESSION_PLIST"
    if [[ -n "$UITEST_RUN_ID" ]]; then
        uitest_account --delete-run "$UITEST_RUN_ID" >/dev/null 2>&1 \
            || echo -e "${YELLOW}⚠ Could not delete test account for run ${UITEST_RUN_ID}; the next mint reaps it after 24h${NC}"
    fi
}
trap cleanup_uitest_session EXIT

# Run UI tests
if [[ "$RUN_UI_TESTS" == "true" ]]; then
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
