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
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$PWD"

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
  SIM_UDID=$(xcrun simctl list devices available -j | python3 -c "
import json,sys
for runtime, devices in json.load(sys.stdin)['devices'].items():
    if 'iOS' not in runtime: continue
    for d in devices:
        if d['name'] == 'iPhone 17 Pro':
            print(d['udid']); raise SystemExit
" 2>/dev/null)
  [ -n "$SIM_UDID" ] || { echo "RESULT: FAILED — no iPhone 17 Pro simulator available"; exit 1; }
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
start_log_capture() {
  if [ "$TARGET" = "ios" ]; then
    [ -n "${SIM_UDID:-}" ] || return 0
    xcrun simctl spawn "$SIM_UDID" log stream --level debug \
      --predicate 'processImagePath CONTAINS "Astrid"' > "$OUT/system-$TARGET.log" 2>/dev/null &
  else
    log stream --level debug --predicate 'processImagePath CONTAINS "Astrid"' \
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
  IOS_MONKEY_MODE="offline"
  [ -f "$SESSION_PLIST" ] && IOS_MONKEY_MODE="signed-in"
  if [ ! -f "$SESSION_PLIST" ] && [ -d "$ROOT/../astrid-web" ]; then
    echo "  Minting a session for uitest@astrid.cc..."
    # --env-file is not optional: tsx does not load .env.local on its own, so without it the
    # mint dies on a missing NEXTAUTH_SECRET and the suite runs signed out.
    COOKIE=$(cd "$ROOT/../astrid-web" && npx tsx --env-file=.env.local scripts/uitest-account.ts --cookie 2>/dev/null | tail -1) || COOKIE=""
    case "$COOKIE" in *"❌"*|"") COOKIE="" ;; esac
    if [ -n "$COOKIE" ]; then
      /usr/libexec/PlistBuddy -c "Add :sessionCookie string $COOKIE" "$SESSION_PLIST" >/dev/null 2>&1 || true
      IOS_MONKEY_MODE="signed-in"
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
    2>&1 | tee "$LOG" | grep -E "Test case|MONKEY_SUMMARY|error:|XCTFail" 
TEST_RC=${PIPESTATUS[0]}
set -e
stop_log_capture

# Whether the run counts is decided here, but NOT acted on until after the log sweep: the sweep is
# the half of this that finds the quiet problems, and an early exit would throw it away.
VERDICT="ok"; VERDICT_WHY=""
if grep -qiE "test case '.*monkeyuitests.*' skipped" "$LOG" 2>/dev/null; then
  VERDICT="failed"
  VERDICT_WHY="the monkey SKIPPED instead of running, so nothing was stressed"
elif [ "$TEST_RC" -ne 0 ]; then
  VERDICT="failed"
  VERDICT_WHY="$SCHEME did not survive the run — search $LOG for XCTFail"
elif ! grep -qiE "test case '.*monkeyuitests.*' passed" "$LOG" 2>/dev/null; then
  # Both output shapes: "Test case 'MonkeyUITests...' passed" under parallel testing, and
  # "Test Case '-[Astrid_AppUITests.MonkeyUITests ...]' passed" without it.
  VERDICT="failed"
  VERDICT_WHY="xcodebuild exited 0 but no monkey test reported passing, so nothing was stressed"
fi

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
  # itself, and haptics on a device that has none. Whatever remains is worth a human's attention.
  echo "  after dropping known test-environment noise:" | tee -a "$FINDINGS"
  printf "%s" "$APP_ERRORS" \
    | grep -viE "XCTAutomationSupport|CoreHaptics|AXRuntime|UIAccessibility" \
    | cut -c1-240 | head -20 | sed 's/^/    /' | tee -a "$FINDINGS" || true
fi

# The loud failures still get an explicit yes/no, because "no lines matched" and "this never
# happened" are different claims and only the second one is worth making.
echo "" | tee -a "$FINDINGS"
for check in "crash:fatal error|Fatal Exception|SIGABRT|EXC_BAD_ACCESS" \
             "Swift runtime trap:Swift runtime failure|precondition failed" \
             "layout constraint break:Unable to simultaneously satisfy" \
             "Core Data error:com.apple.CoreData.*(error|Fault)|CoreData: error" \
             "app hang:hang detected|Hang detected"; do
  label="${check%%:*}"; pattern="${check#*:}"
  n=$(printf "%s" "$APP_ERRORS" | grep -ciE "$pattern" || true)
  printf "  %-24s %s\n" "$label" "${n:-0}" | tee -a "$FINDINGS"
done

echo ""
if [ "$VERDICT" = "ok" ]; then
  green "✓ The app survived: no crash, no hang, still driveable"
else
  echo "  ✗ $VERDICT_WHY"
fi
echo "  Log sweep: $FINDINGS"
echo "  Full app log: $OUT/system-$TARGET.log ($(wc -l < "$OUT/system-$TARGET.log" 2>/dev/null | tr -d ' ') lines)"

echo ""
if [ "$VERDICT" = "ok" ]; then
  if [ "$TARGET" = "ios" ] && [ "$IOS_MONKEY_MODE" = "offline" ]; then
    echo "RESULT: OK (OFFLINE — signed-in paths not stressed) — $SCHEME survived $ACTIONS random actions. Log findings counted in $FINDINGS"
    exit 0
  fi
  echo "RESULT: OK — $SCHEME survived $ACTIONS random actions. Log findings counted in $FINDINGS"
  exit 0
fi
echo "RESULT: FAILED — $VERDICT_WHY. Details: $LOG"
exit 1
