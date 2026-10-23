#!/bin/bash
# test-monkey-verdict.sh — self-test for monkey-test.sh's verdict (AITD-530).
#
# The weekly Mac monkey failed four Mondays running on a locked screen and reported it as "did
# not survive": a month-old false red. The verdict is now a pure function of the xcodebuild log
# and exit code, reachable with `monkey-test.sh --classify <log> <rc>`, so it is pinned here.
set -uo pipefail
cd "$(dirname "$0")/.."
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
FAILS=0

check() {  # name, expected verdict word, rc, log body
  printf "%s\n" "$4" > "$TMP/log"
  local got; got=$(./scripts/monkey-test.sh --classify "$TMP/log" "$3" 2>&1 | head -1)
  if [[ "$got" == "$2"* ]]; then echo "  ✓ $1"; else echo "  ✗ $1 — expected $2, got: $got"; FAILS=$((FAILS+1)); fi
}

echo "monkey-test.sh verdict"
check "locked screen is HARNESS, not a crash" harness 65 \
  "/x/MacMonkeyUITests.swift:36: error: -[Astrid_MacUITests.MacMonkeyUITests testMonkey] : Failed to activate application 'Graceful-Tools-Inc.Astrid-App at /x/Astrid.app' (current state: Running Background)
Test Case '-[Astrid_MacUITests.MacMonkeyUITests testMonkeyStressesTheMacAppWithoutCrashingOrHanging]' failed (62.878 seconds)."
check "a real failure is FAILED" failed 65 \
  "Test Case '-[Astrid_AppUITests.MonkeyUITests testMonkey]' failed (12.0 seconds)."
check "a skipped monkey is FAILED" failed 0 \
  "Test Case '-[Astrid_AppUITests.MonkeyUITests testMonkey]' skipped (1.0 seconds)."
check "exit 0 with no passing test is FAILED" failed 0 "nothing here"
check "a pass is OK" ok 0 \
  "Test Case '-[Astrid_AppUITests.MonkeyUITests testMonkey]' passed (80.0 seconds)."

[ "$FAILS" -eq 0 ] && echo "RESULT: OK — monkey verdict" || { echo "RESULT: FAILED — $FAILS monkey verdict case(s)"; exit 1; }
