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

# --- The stall alert, and the run that causes one (AITD-426) ------------------------
#
# The tree guards are RIGHT to refuse once. On 2026-09-22 they refused 25 times across 12
# hours with the queue non-empty the whole time, and said so only in a log nobody reads
# unless they already suspect a problem — Jon found out by asking. The skip is not the
# defect; the silence is.
#
# These need the guards to actually run, which FIXALL_FORCE=1 turns off, and they need a
# tree whose cleanliness the test controls rather than whatever this checkout happens to
# be mid-run. So the loop runs in a throwaway git repo: REPO comes from $0, so a copy of
# the script at $SANDBOX/repo/scripts/ makes $SANDBOX/repo the tree it guards and
# $SANDBOX/astrid-web the sibling it shells out to.
SANDBOX="$TMP/sandbox"
mkdir -p "$SANDBOX/repo/scripts" "$SANDBOX/astrid-web"
cp "$LOOP" "$SANDBOX/repo/scripts/fixall-loop.sh"
chmod +x "$SANDBOX/repo/scripts/fixall-loop.sh"
(
  cd "$SANDBOX/repo"
  git init -q -b main .
  git config user.email t@example.com
  git config user.name  Test
  # The copied loop is COMMITTED, not left untracked: clean_sandbox runs `git clean -fd`,
  # which would otherwise delete the very script under test.
  git add -A
  git commit -q -m init
) >/dev/null 2>&1

# A claude that does what the 17:30 run did: edits a file, then ends its turn anyway.
cat > "$TMP/bin/claude-leaves-mess" <<'STUB'
#!/bin/bash
echo "claude $*" >> "$CALLS"
echo "half-finished" > leftover.txt
exit 0
STUB
chmod +x "$TMP/bin/claude-leaves-mess"

STALL_STATE="$TMP/stall.state"

run_sandbox() {  # run_sandbox [claude-bin]  → $OUT, $STATUS, $CALLS
  : > "$CALLS"
  FIXALL_TSX="$TMP/bin/tsx" \
  CLAUDE_BIN="${1:-$TMP/bin/claude}" \
  FIXALL_MAX_MINUTES=1 \
  FIXALL_MAX_USD= \
  FIXALL_STALL_STATE="$STALL_STATE" \
  FIXALL_STALL_ALERT_AFTER=3 \
  STUB_CLAUDE_EXIT=0 \
  STUB_QUEUE_EXIT=0 \
  "$SANDBOX/repo/scripts/fixall-loop.sh" > "$TMP/out.txt" 2>&1
  STATUS=$?
  OUT=$(cat "$TMP/out.txt")
}

dirty_sandbox() { echo "uncommitted" > "$SANDBOX/repo/work-in-progress.txt"; }
clean_sandbox() { ( cd "$SANDBOX/repo" && git clean -qfd && git checkout -q -- . ); }

# `called` matches within ONE logged line, which the run summaries are. A stall alert is
# markdown with headings and a fenced block, so its words land on different lines of the
# log — this reads the whole file instead.
posted() {  # posted <description> <pattern…>
  local desc="$1"; shift
  grep -q "post-list-message.ts" "$CALLS" || { bad "$desc (nothing was posted)" "$(cat "$CALLS")"; return 0; }
  local want
  for want in "$@"; do
    grep -qF -- "$want" "$CALLS" || { bad "$desc (no \"$want\" in the message)" "$(cat "$CALLS")"; return 0; }
  done
  ok
}

# One skip is the healthy outcome and must stay silent — at two ticks an hour, a per-tick
# alert is just a different way of being ignored.
rm -f "$STALL_STATE"
dirty_sandbox
run_sandbox
not_called "post-list-message.ts" "the first dirty-tree skip stays quiet"
if echo "$OUT" | tail -1 | grep -q '^RESULT: SKIPPED'; then ok
else bad "a dirty tree still ends on RESULT: SKIPPED" "$OUT"; fi

# The second is still within tolerance…
run_sandbox
not_called "post-list-message.ts" "the second consecutive skip is still quiet"

# …the third is the stall, and it says so once, naming what is in the way.
run_sandbox
posted "the third consecutive skip posts to the list chat"
posted "…and names the branch it is stuck on" "On branch \`main\`"
posted "…and names the file holding it up" "work-in-progress.txt"
posted "…and says whether work is piling up behind it" "QUEUE:"

# Once per stall, not once per tick.
run_sandbox
not_called "post-list-message.ts" "a fourth skip does not post again — once per stall"

# Getting past the guards resets the counter, so the NEXT stall is heard too.
clean_sandbox
run_sandbox
not_called "post-list-message.ts" "a tick that gets past the guards posts nothing itself"
dirty_sandbox
run_sandbox
not_called "post-list-message.ts" "…and the count starts again from one after it"

# The wrong-branch guard is the same failure class and gets the same treatment.
rm -f "$STALL_STATE"
clean_sandbox
( cd "$SANDBOX/repo" && git checkout -q -b some-fix )
run_sandbox; run_sandbox; run_sandbox
posted "three ticks stuck off main also post once" "HEAD is on some-fix, not main"
( cd "$SANDBOX/repo" && git checkout -q main )

# --- The other half: a run that leaves the tree dirty is a FAILED run ---------------
# `claude -p` exiting 0 is not enough. The 17:30 run exited 0 with four modified files
# still uncommitted, so the loop recorded OK and nothing downstream treated it as a
# failure — the wake keys were marked seen rather than struck, and the stall was left to
# be inferred from the next tick's skip.
rm -f "$STALL_STATE"
clean_sandbox
run_sandbox "$TMP/bin/claude-leaves-mess"
if echo "$OUT" | tail -1 | grep -q '^RESULT: FAILED'; then ok
else bad "a run that leaves the tree dirty must not report OK" "$OUT"; fi
called "…and its wake keys get a strike, not a mute" \
       "agent-queue-status.ts" "--mark-seen" "--failed"
posted "…and it says so on the board, since the run cannot report for itself" \
       "left work uncommitted" "leftover.txt"
clean_sandbox

echo ""
if [ "$FAIL" = 0 ]; then echo "✓ fixall-loop: $PASS checks passed"; exit 0; fi
echo "✗ fixall-loop: $FAIL failed, $PASS passed"; exit 1
