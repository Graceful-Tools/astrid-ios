#!/bin/bash
#
# test-fixall-loop.sh — the regression test for scripts/fixall-loop.sh (Task AITD-422).
#
# What it pins is the TWO-PHASE WAKE. An inbox or lane item wakes exactly one run, which the
# seen-file enforces. If that file is written at the PREFLIGHT, a run that crashes, is
# watchdog-killed or runs out of budget has already muted the item that woke it — "one run per
# item" quietly becomes "one attempt ever". So the preflight must defer the write
# (--no-write-seen, handing its keys back on a KEYS: line) and the run's OUTCOME must record
# them: --mark-seen after a finished run, --mark-seen --failed after one that died.
#
# The loop is run for real against stubs: a fake `tsx` that answers for agent-queue-status.ts
# and the session lock and logs every call, and a fake `claude` whose exit code the test picks.
# Nothing here touches the network, the board, the real working-tree lock, or Xcode Cloud.
#
# What is pinned:
#   - the preflight defers the seen-file write and its keys are read back;
#   - a finished run marks exactly those keys seen, with no strike;
#   - a run that died gives them a strike instead (--failed) and does not mute them outright;
#   - the keys reach the second phase verbatim;
#   - marking happens BEFORE the RESULT: line, which stays last in the output;
#   - a skipped tick (nothing queued) marks nothing — no run was woken, so nothing was answered.
set -u
cd "$(dirname "$0")/.."

LOOP="$PWD/scripts/fixall-loop.sh"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin"
export CALLS="$TMP/calls.log"

# The fake tsx: answers for every script the loop shells out to, and records the argv of each.
cat > "$TMP/bin/tsx" <<'STUB'
#!/bin/bash
echo "$*" >> "$CALLS"
case "$*" in
  *fixall-session.ts*)      exit 0 ;;
  *post-list-message.ts*)   exit 0 ;;
  *agent-queue-status.ts*--mark-seen*)
    echo "SEEN: recorded"; exit 0 ;;
  *agent-queue-status.ts*)
    echo "QUEUE: 1 task ready for claude"
    echo 'KEYS: ["comment:c1","task:t1"]'
    exit "${STUB_QUEUE_EXIT:-0}" ;;
esac
exit 0
STUB
chmod +x "$TMP/bin/tsx"

# The fake claude: never reads the board, exits however the test asks.
cat > "$TMP/bin/claude" <<'STUB'
#!/bin/bash
echo "claude $*" >> "$CALLS"
exit "${STUB_CLAUDE_EXIT:-0}"
STUB
chmod +x "$TMP/bin/claude"

PASS=0; FAIL=0
ok()   { PASS=$((PASS+1)); }
bad()  { FAIL=$((FAIL+1)); echo "✗ $1"; [ -n "${2:-}" ] && echo "$2" | sed 's/^/    /'; return 0; }

# The loop's output goes to a FILE, never a command substitution: the watchdog it spawns
# outlives the run (killing the subshell orphans its `sleep`), and an orphan holding the read
# end of a pipe would make `$(…)` block for the whole watchdog interval.
run() {  # run <claude-exit> <queue-exit>   → $OUT (loop output), $CALLS (argv log), $STATUS
  : > "$CALLS"
  FIXALL_FORCE=1 \
  FIXALL_TSX="$TMP/bin/tsx" \
  CLAUDE_BIN="$TMP/bin/claude" \
  FIXALL_MAX_MINUTES=1 \
  FIXALL_MAX_USD= \
  STUB_CLAUDE_EXIT="$1" \
  STUB_QUEUE_EXIT="$2" \
  "$LOOP" > "$TMP/out.txt" 2>&1
  STATUS=$?
  OUT=$(cat "$TMP/out.txt")
}

# A call to agent-queue-status.ts matching every pattern given, and none of the "!" ones.
called() {  # called <description> <pattern…>
  local desc="$1"; shift
  local line found=0
  while IFS= read -r line; do
    local want all=1
    for want in "$@"; do
      case "$want" in
        '!'*) case "$line" in *"${want#!}"*) all=0 ;; esac ;;
        *)    case "$line" in *"$want"*) ;; *) all=0 ;; esac ;;
      esac
    done
    [ "$all" = 1 ] && found=1
  done < "$CALLS"
  if [ "$found" = 1 ]; then ok; else bad "$desc" "$(cat "$CALLS")"; fi
}

not_called() {  # not_called <pattern> <description>
  if grep -q -- "$1" "$CALLS"; then bad "$2" "$(cat "$CALLS")"; else ok; fi
}

[ -x "$LOOP" ] || { echo "✗ $LOOP is missing or not executable"; exit 1; }

# --- Phase one: the preflight must NOT write the seen-file -------------------------
run 0 0
called "preflight defers the seen-file write (--no-write-seen)" \
       "agent-queue-status.ts" "--no-write-seen" "!--mark-seen"

# --- Phase two, finished run: mark the keys seen -----------------------------------
called "a finished run marks its wake keys seen" \
       "agent-queue-status.ts" "--mark-seen" "--seen-keys" "!--failed"
called "…and passes the preflight's keys through verbatim" \
       "--seen-keys" '["comment:c1","task:t1"]'
if echo "$OUT" | tail -1 | grep -q '^RESULT: OK'; then ok
else bad "RESULT: OK is the last line after a finished run" "$OUT"; fi
if [ "$STATUS" = 0 ]; then ok; else bad "a finished run exits 0 (got $STATUS)" "$OUT"; fi

# --- Phase two, run that died: a strike, not a mute --------------------------------
run 3 0
called "a run that died gives its wake keys a strike (--failed)" \
       "agent-queue-status.ts" "--mark-seen" "--failed" "--seen-keys"
called "…with the same keys" "--seen-keys" '["comment:c1","task:t1"]'
if echo "$OUT" | tail -1 | grep -q '^RESULT: FAILED'; then ok; else bad "a dead run still ends on RESULT: FAILED, last" "$OUT"; fi

# A watchdog kill is the case this exists for: 128+signal, not a clean non-zero exit.
run 143 0
called "a watchdog-killed run gives a strike too, it does not mute" \
       "agent-queue-status.ts" "--mark-seen" "--failed"

# --- A quiet tick answers nothing, so it marks nothing -----------------------------
run 0 3
not_called "--mark-seen" "a skipped tick must not mark anything seen"
not_called "^claude " "a skipped tick must not start a session"
if echo "$OUT" | tail -1 | grep -q '^RESULT: SKIPPED'; then ok; else bad "a quiet tick ends on RESULT: SKIPPED" "$OUT"; fi

echo ""
if [ "$FAIL" = 0 ]; then echo "✓ fixall-loop: $PASS checks passed"; exit 0; fi
echo "✗ fixall-loop: $FAIL failed, $PASS passed"; exit 1
