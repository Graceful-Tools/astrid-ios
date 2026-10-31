#!/bin/bash
# test-monkey-verdict.sh — self-test for monkey-test.sh's verdict (AITD-530).
#
# The weekly Mac monkey failed four Mondays running on a locked screen and reported it as "did
# not survive": a month-old false red. The verdict is now a pure function of the xcodebuild log
# and exit code, reachable with `monkey-test.sh --classify <log> <rc>`, so it is pinned here.
set -uo pipefail
cd "$(dirname "$0")/.."
TMP=$(mktemp -d "${TMPDIR:-/tmp}/astrid-monkey-test.XXXXXXXX") || exit 1
if [[ "${ASTRID_KEEP_TEST_FIXTURES:-0}" != 1 ]]; then trap 'rm -rf "$TMP"' EXIT; fi
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

# The capture level (AITD-548). At `debug` the stream itself switches on every framework's debug
# logging in the app process; XCTest's per-action accessibility snapshots then emit ~1.5M lines
# in 200 actions and the OS quarantines the app's log, hiding everything after. The sweep reads
# only Error and Fault lines, so `info` loses it nothing.
level() {  # name, expected, env value ("" for unset)
  local got
  if [ -n "$3" ]; then got=$(ASTRID_MONKEY_LOG_LEVEL="$3" ./scripts/monkey-test.sh --capture-level 2>/dev/null)
  else got=$(env -u ASTRID_MONKEY_LOG_LEVEL ./scripts/monkey-test.sh --capture-level 2>/dev/null); fi
  if [ "$got" = "$2" ]; then echo "  ✓ $1"; else echo "  ✗ $1 — expected $2, got: $got"; FAILS=$((FAILS+1)); fi
}
echo "monkey-test.sh capture level"
level "the log is captured at info by default, never debug" info ""
level "debug is there when asked for, for a deliberate deep dive" debug debug
level "an unknown level falls back to info" info verbose

[ "$FAILS" -eq 0 ] && echo "RESULT: OK — monkey verdict" || { echo "RESULT: FAILED — $FAILS monkey verdict case(s)"; exit 1; }
