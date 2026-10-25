#!/bin/bash
#
# monkey-test.sh — random-input stress run against the iOS or Mac app, plus a sweep of what the
# app logged while it was being hammered.
#
# The XCUITest half (MonkeyUITests / MacMonkeyUITests) asserts survival: no crash, no hang, still
# driveable. That catches the loud failures. The quiet ones — a constraint breaking on every
# frame, Core Data complaining, a request failing, the main thread being blocked — only show up
# in the log, so this collects it and counts what it finds.
#
#   ./scripts/monkey-test.sh ios              # 150 random actions, then the log sweep
#   ./scripts/monkey-test.sh mac
#   ./scripts/monkey-test.sh ios --actions 400 --seed 7
#
# Every run ends with one line starting `RESULT:`. Findings land in build/monkey/.
#   RESULT: OK       exit 0 — the app survived
#   RESULT: FAILED   exit 1 — the app did not survive, or nothing was stressed
#   RESULT: HARNESS  exit 3 — the machine could not run a UI test (locked screen, app never
#                    reached the foreground). Says nothing about the app either way.
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$PWD"

# The verdict, as a function of the xcodebuild log and its exit code alone, so
# scripts/test-monkey-verdict.sh can pin it: `monkey-test.sh --classify <log> <rc>` prints
# "<verdict> — <why>" and runs nothing.
classify() {
  local log="$1" rc="$2"
  VERDICT="ok"; VERDICT_WHY=""
  if grep -q "Failed to activate application" "$log" 2>/dev/null; then
    # Checked first: it fails the test, but it is the machine, not the app (see the lock check).
    VERDICT="harness"
    VERDICT_WHY="${SCHEME:-the app} launched but never reached the foreground (locked screen or another app holding focus)"
  elif grep -qiE "test case '.*monkeyuitests.*' skipped" "$log" 2>/dev/null; then
    VERDICT="failed"
    VERDICT_WHY="the monkey SKIPPED instead of running, so nothing was stressed"
  elif [ "$rc" -ne 0 ]; then
    VERDICT="failed"
    VERDICT_WHY="${SCHEME:-the app} did not survive the run — search $log for XCTFail"
  elif ! grep -qiE "test case '.*monkeyuitests.*' passed" "$log" 2>/dev/null; then
    # Both output shapes: "Test case 'MonkeyUITests...' passed" under parallel testing, and
    # "Test Case '-[Astrid_AppUITests.MonkeyUITests ...]' passed" without it.
    VERDICT="failed"
    VERDICT_WHY="xcodebuild exited 0 but no monkey test reported passing, so nothing was stressed"
  fi
}

if [ "${1:-}" = "--classify" ]; then
  classify "${2:?log path}" "${3:?exit code}"
  echo "$VERDICT — ${VERDICT_WHY:-survived}"
  exit 0
fi

# The level the system log is captured at (AITD-548). NOT debug: debug messages are generated only
# while someone streams at that level, so `--level debug` switched on every framework's debug
# logging inside the app. XCTest's accessibility snapshot on each action then made the app emit
# ~1.5M lines in 200 actions — Accessibility naming colours through CFBundle string lookups,
# CFPrefs reading XCTest's automation keys — the OS quarantined its log (QUARANTINED DUE TO HIGH
# LOGGING VOLUME) and dropped every line after, real errors included. The app's own code wrote
# six. The sweep below reads only Error and Fault lines, which `info` keeps; debug also wrote the
# run's session cookie into the file, as CFPrefs echoed the launch argument.
# ASTRID_MONKEY_LOG_LEVEL=debug still gets a debug capture, for a deliberate deep dive.
capture_level() {
  case "${ASTRID_MONKEY_LOG_LEVEL:-info}" in
    default|info|debug) echo "${ASTRID_MONKEY_LOG_LEVEL:-info}" ;;
    *) echo "  ? ASTRID_MONKEY_LOG_LEVEL=$ASTRID_MONKEY_LOG_LEVEL is not default, info or debug — using info" >&2
       echo info ;;
  esac
}

if [ "${1:-}" = "--capture-level" ]; then
  capture_level
  exit 0
fi

TARGET="${1:-}"; shift || true
ACTIONS=150; SEED=""; HANG=10
while [ $# -gt 0 ]; do
  case "$1" in
    --actions) ACTIONS="${2:-150}"; shift ;;
    --seed)    SEED="${2:-}"; shift ;;
    --hang)    HANG="${2:-10}"; shift ;;
    *) echo "RESULT: FAILED — unknown option \"$1\""; exit 2 ;;
  esac
  shift
done

case "$TARGET" in
  ios) SCHEME="Astrid App"; SUITE="Astrid AppUITests/MonkeyUITests"
       CONFIG_DIR="Astrid AppUITests" ;;
  mac) SCHEME="Astrid Mac"; SUITE="Astrid MacUITests/MacMonkeyUITests"
       CONFIG_DIR="Astrid MacUITests"; DESTINATION="platform=macOS" ;;
  *) echo "RESULT: FAILED — first argument must be ios or mac"; exit 2 ;;
esac

case "$TARGET" in
  ios) APP_PROCESS="Astrid App" ;;
  mac) APP_PROCESS="Astrid" ;;
esac

OUT="$ROOT/build/monkey"
mkdir -p "$OUT"
LOG="$OUT/monkey-$TARGET.log"
FINDINGS="$OUT/findings-$TARGET.txt"

green() { printf "\033[0;32m%s\033[0m\n" "$1"; }
step()  { printf "\n\033[0;36m=== %s ===\033[0m\n" "$1"; }

step "Monkey: $SCHEME"
echo "  $ACTIONS actions, hang threshold ${HANG}s${SEED:+, seed $SEED}"

# Pin ONE simulator and turn parallel testing off, so the run happens on a device whose UDID is
# known. With parallel testing on, xcodebuild runs the tests on a fresh CLONE with its own UDID —
# so a log stream attached to the booted device captures nothing at all, which is how the first
# run produced an empty log while reporting success.
if [ "$TARGET" = "ios" ]; then
  MONKEY_DEVICE="${ASTRID_MONKEY_SIMULATOR_NAME:-iPhone 17 Pro}"
  SIM_UDID=$(xcrun simctl list devices available -j | MONKEY_DEVICE="$MONKEY_DEVICE" python3 -c "
import json,os,sys
for runtime, devices in json.load(sys.stdin)['devices'].items():
    if 'iOS' not in runtime: continue
    for d in devices:
        if d['name'] == os.environ['MONKEY_DEVICE']:
            print(d['udid']); raise SystemExit
" 2>/dev/null)
  # A name alone can match several runtimes (an iPhone 17 on iOS 26.5 AND on 27.0); to replay
  # a CI failure on the exact device it ran on, pin the UDID (AITD-524).
  SIM_UDID="${ASTRID_MONKEY_SIMULATOR_UDID:-$SIM_UDID}"
  [ -n "$SIM_UDID" ] || { echo "RESULT: FAILED — no $MONKEY_DEVICE simulator available (set ASTRID_MONKEY_SIMULATOR_NAME)"; exit 1; }
  xcrun simctl boot "$SIM_UDID" 2>/dev/null || true
  xcrun simctl bootstatus "$SIM_UDID" -b >/dev/null 2>&1 || true
  DESTINATION="platform=iOS Simulator,id=$SIM_UDID"
  echo "  Simulator $SIM_UDID"
fi

# macOS UI tests cannot attach a test runner while developer mode is off: every attach then needs
# an interactive admin authentication, and a non-interactive xcodebuild run has no way to answer
# it. The failure arrives as LocalAuthentication Code=-4 "System authentication is running.", which
# reads like a stuck password dialog and sends you hunting for a window that is not there.
if [ "$TARGET" = "mac" ] && ! DevToolsSecurity -status 2>/dev/null | grep -q enabled; then
  echo ""
  echo "RESULT: FAILED — developer mode is off on this Mac, so the UI-test runner cannot start."
  echo "  Fix (needs your password, once per machine): sudo DevToolsSecurity -enable"
  exit 1
fi

# A locked screen puts a shield window over every app, so the app under test launches but can
# never come to the foreground. XCUITest then fails `launch()` itself with "Failed to activate
# application … (current state: Running Background)", and the app log shows AppKit refusing to
# vend accessibility elements because the window "is lower than shield(2001)". The weekly Mac run
# hit exactly this four Mondays running and reported it as "did not survive" (AITD-530). Ask first.
if [ "$TARGET" = "mac" ] && ioreg -n Root -d1 -a 2>/dev/null | plutil -extract IOConsoleUsers xml1 -o - - 2>/dev/null \
     | grep -A1 CGSSessionScreenIsLocked | grep -q "<true/>"; then
  echo ""
  echo "RESULT: HARNESS — the screen is locked, so the Mac app cannot reach the foreground. Unlock it and re-run."
  exit 3
fi

# The knobs travel in a bundle resource, not the environment: xcodebuild does not forward the
# shell environment to the UI-test runner, so `--actions 25` silently ran 150 until this existed.
CONFIG_PLIST="$ROOT/$CONFIG_DIR/MonkeyConfig.plist"
rm -f "$CONFIG_PLIST"
/usr/libexec/PlistBuddy \
  -c "Add :actions integer $ACTIONS" \
  -c "Add :hangSeconds integer $HANG" \
  ${SEED:+-c "Add :seed integer $SEED"} \
  "$CONFIG_PLIST" >/dev/null
echo "  Config written for the test bundle"

# The app's own log, captured for the duration of the run. On iOS this is the simulator's; on
# macOS the system log filtered to the app. Started before the run and stopped after, so the
# window covers exactly the monkey's actions and nothing else.
STREAM_PID=""
LOG_LEVEL=$(capture_level)
start_log_capture() {
  if [ "$TARGET" = "ios" ]; then
    [ -n "${SIM_UDID:-}" ] || return 0
    xcrun simctl spawn "$SIM_UDID" log stream --level "$LOG_LEVEL" \
      --predicate 'processImagePath CONTAINS "Astrid"' > "$OUT/system-$TARGET.log" 2>/dev/null &
  else
    log stream --level "$LOG_LEVEL" --predicate 'processImagePath CONTAINS "Astrid"' \
      > "$OUT/system-$TARGET.log" 2>/dev/null &
  fi
  STREAM_PID=$!
}
stop_log_capture() {
  # `|| true` on the kill: this runs twice — once after the test, once from the EXIT trap — and
  # the second kill fails because the process is already gone. Under `set -e` that failure
  # aborted the trap before `return 0`, so the script exited 1 while printing RESULT: OK.
  if [ -n "$STREAM_PID" ]; then kill "$STREAM_PID" 2>/dev/null || true; fi
  STREAM_PID=""
  rm -f "${CONFIG_PLIST:-}" 2>/dev/null || true
  return 0
}
trap stop_log_capture EXIT INT TERM

# iOS needs the shared test account; the Mac suite is hermetic and runs offline.
if [ "$TARGET" = "ios" ]; then
  SESSION_PLIST="$ROOT/Astrid AppUITests/UITestSession.plist"
  if [ ! -f "$SESSION_PLIST" ] && [ -d "$ROOT/../astrid-web" ]; then
    echo "  Minting a session for uitest@astrid.cc..."
    # --env-file is not optional: tsx does not load .env.local on its own, so without it the
    # mint dies on a missing NEXTAUTH_SECRET and the suite runs signed out.
    COOKIE=$(cd "$ROOT/../astrid-web" && npx tsx --env-file=.env.local scripts/uitest-account.ts --cookie 2>/dev/null | tail -1) || COOKIE=""
    case "$COOKIE" in *"❌"*|"") COOKIE="" ;; esac
    if [ -n "$COOKIE" ]; then
      /usr/libexec/PlistBuddy -c "Add :sessionCookie string $COOKIE" "$SESSION_PLIST" >/dev/null 2>&1 || true
      echo "  Signed-in run"
    else
      echo "  No session could be minted — the monkey will run OFFLINE instead of skipping."
    fi
  fi
  # Never leave a live credential in the working tree. A function, not an inline command list:
  # the EXIT trap's final status leaks into the script's own exit status, so a stray non-zero
  # from `rm` reported a perfectly good run as a failure.
  cleanup_ios() { stop_log_capture; rm -f "$SESSION_PLIST" 2>/dev/null; return 0; }
  trap cleanup_ios EXIT INT TERM
fi

start_log_capture

step "Running"
set +e
env MONKEY_ACTIONS="$ACTIONS" MONKEY_HANG_SECONDS="$HANG" ${SEED:+MONKEY_SEED=$SEED} \
  xcodebuild test \
    -scheme "$SCHEME" \
    -destination "$DESTINATION" \
    -only-testing:"$SUITE" \
    -parallel-testing-enabled NO \
    -collect-test-diagnostics never \
    2>&1 | tee "$LOG" | grep -E "Test case|MONKEY_SUMMARY|error:|XCTFail" 
TEST_RC=${PIPESTATUS[0]}
set -e
stop_log_capture

# Whether the run counts is decided here, but NOT acted on until after the log sweep: the sweep is
# the half of this that finds the quiet problems, and an early exit would throw it away.
classify "$LOG" "$TEST_RC"

step "What the app logged while being hammered"
# Severity first, keywords second.
#
# The first version of this swept the whole stream for words like "error", "watchdog" and
# "jetsam", and every category it lit up was a false positive: CoreHaptics failing in a simulator
# with no haptics engine, FrontBoard REGISTERING a method called setJetsamPriority:, framework
# chatter containing the word error. It reported "36 Core Data errors" on a run that had none,
# which is worse than reporting nothing.
#
# So: take only lines the OS itself marked Error or Fault, only from the app's own process (the
# XCTest runner is not the app), then group them by the subsystem that emitted them. That turns
# a keyword guess into a fact — and leaves the interesting ones visible instead of buried.
: > "$FINDINGS"
APP_ERRORS=$(awk -v proc="$APP_PROCESS: " '$4 ~ /^(Error|Fault)$/ && index($0, proc) {print}' "$OUT/system-$TARGET.log" 2>/dev/null || true)
TOTAL=$(printf "%s" "$APP_ERRORS" | grep -c . || true)
echo "  Error/Fault lines from the app process: ${TOTAL:-0}" | tee -a "$FINDINGS"
echo "" | tee -a "$FINDINGS"

if [ "${TOTAL:-0}" -gt 0 ]; then
  echo "  by subsystem:" | tee -a "$FINDINGS"
  printf "%s" "$APP_ERRORS" | grep -oE "\([A-Za-z_.]+\)" | sort | uniq -c | sort -rn | head -12 \
    | sed 's/^/    /' | tee -a "$FINDINGS"
  echo "" | tee -a "$FINDINGS"

  # What is left after the frameworks that are noisy BY DESIGN in a test simulator: the harness
  # itself, and haptics on a device that has none (CoreHaptics, and the keyboard's
  # UIKBFeedbackGenerator failing to build a CHHapticPattern). Whatever remains is worth a human's attention.
  echo "  after dropping known test-environment noise:" | tee -a "$FINDINGS"
  # 2>/dev/null: `head` closes the pipe early, and printf would report the broken pipe.
  printf "%s" "$APP_ERRORS" 2>/dev/null \
    | grep -viE "XCTAutomationSupport|CoreHaptics|UIKBFeedbackGenerator|AXRuntime|UIAccessibility|AccessibilitySettingsLoader|libCoreFSCache" \
    | cut -c1-240 | head -20 | sed 's/^/    /' | tee -a "$FINDINGS" || true
fi

# The loud failures still get an explicit yes/no, because "no lines matched" and "this never
# happened" are different claims and only the second one is worth making.
echo "" | tee -a "$FINDINGS"
for check in "crash:fatal error|Fatal Exception|SIGABRT|EXC_BAD_ACCESS" \
             "Swift runtime trap:Swift runtime failure|precondition failed" \
             "layout constraint break:Unable to simultaneously satisfy" \
             "Core Data error:com.apple.CoreData.*(error|Fault)|CoreData: error" \
             "app hang:hang detected|Hang detected" \
             "log volume quarantined:QUARANTINED DUE TO HIGH LOGGING VOLUME"; do
  label="${check%%:*}"; pattern="${check#*:}"
  n=$(printf "%s" "$APP_ERRORS" | grep -ciE "$pattern" || true)
  printf "  %-24s %s\n" "$label" "${n:-0}" | tee -a "$FINDINGS"
done

echo ""
if [ "$VERDICT" = "ok" ]; then
  green "✓ The app survived: no crash, no hang, still driveable"
elif [ "$VERDICT" = "harness" ]; then
  echo "  ? $VERDICT_WHY — the run says nothing about the app"
else
  echo "  ✗ $VERDICT_WHY"
fi
echo "  Log sweep: $FINDINGS"
echo "  Full app log: $OUT/system-$TARGET.log ($(wc -l < "$OUT/system-$TARGET.log" 2>/dev/null | tr -d ' ') lines)"

echo ""
if [ "$VERDICT" = "ok" ]; then
  echo "RESULT: OK — $SCHEME survived $ACTIONS random actions. Log findings counted in $FINDINGS"
  exit 0
fi
if [ "$VERDICT" = "harness" ]; then
  echo "RESULT: HARNESS — $VERDICT_WHY. Details: $LOG"
  exit 3
fi
echo "RESULT: FAILED — $VERDICT_WHY. Details: $LOG"
exit 1
