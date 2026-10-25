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
#   - a skipped tick (nothing queued) marks nothing — no run was woken, so nothing was answered;
#   - a run whose own last RESULT: line says FAILED is FAILED even when it exits 0 (AITD-440).
set -u
cd "$(dirname "$0")/.."

LOOP="$PWD/scripts/fixall-loop.sh"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin"
mkdir -p "$TMP/shared-tooling"
export ASTRID_WEB_DIR="$TMP/shared-tooling"
export CALLS="$TMP/calls.log"

# The fake tsx: answers for every script the loop shells out to, and records the argv of each.
cat > "$TMP/bin/tsx" <<'STUB'
#!/bin/bash
echo "$*" >> "$CALLS"
case "$*" in
  *fixall-session.ts*)      exit 0 ;;
  *fixall-pause.ts*yield*)
    # 2 = someone is working this Mac, 1 = state unreadable, 0 = go.
    [ "${STUB_YIELD_EXIT:-0}" = "2" ] && echo "claude-code (pid 999) is working /w/web — this tick stands down"
    [ "${STUB_YIELD_EXIT:-0}" = "1" ] && echo "boom"
    exit "${STUB_YIELD_EXIT:-0}" ;;
  *post-list-message.ts*)   exit 0 ;;
  *open-fixall-prs.ts*)     exit "${STUB_PR_EXIT:-0}" ;;
  *release-stuck-doing.ts*--claims-file*) exit "${STUB_RELEASE_EXIT:-0}" ;;
  *agent-queue-status.ts*--mark-seen*)
    echo "SEEN: recorded"; exit "${STUB_SEEN_EXIT:-0}" ;;
  *agent-queue-status.ts*)
    echo "${STUB_QUEUE_LINE:-QUEUE: 1 task ready for claude}"
    echo 'KEYS: ["comment:c1","task:t1"]'
    exit "${STUB_QUEUE_EXIT:-0}" ;;
esac
exit 0
STUB
chmod +x "$TMP/bin/tsx"

# The fake claude: never reads the board, exits however the test asks. It records
# its own pid so the caffeinate checks can prove the assertion names THIS process.
cat > "$TMP/bin/claude" <<'STUB'
#!/bin/bash
echo "claude $*" >> "$CALLS"
echo "$$" > "$CLAUDE_PID_FILE"
# STUB_CLAUDE_SLEEP keeps the fake run alive for a moment. A run that exits
# instantly is killed by the loop's own `kill "$CAFFEINATE_PID"` before the
# caffeinate stub is ever scheduled, so the assertion it recorded would be
# missing for a reason that cannot happen with the real binary.
sleep "${STUB_CLAUDE_SLEEP:-0}"
exit "${STUB_CLAUDE_EXIT:-0}"
STUB
chmod +x "$TMP/bin/claude"
export CLAUDE_PID_FILE="$TMP/claude.pid"

# The fake caffeinate: records the assertion the loop asks for and returns at once.
# The real one would hold until the watched pid exits, which is the whole point of
# -w, so a stub is the only way to see the arguments without waiting on the run.
cat > "$TMP/bin/caffeinate" <<'STUB'
#!/bin/bash
echo "caffeinate $*" >> "$CALLS"
STUB
chmod +x "$TMP/bin/caffeinate"

PASS=0; FAIL=0
ok()   { PASS=$((PASS+1)); }
bad()  { FAIL=$((FAIL+1)); echo "✗ $1"; [ -n "${2:-}" ] && echo "$2" | sed 's/^/    /'; return 0; }

# The loop's output goes to a FILE, never a command substitution: the watchdog it spawns
# outlives the run (killing the subshell orphans its `sleep`), and an orphan holding the read
# end of a pipe would make `$(…)` block for the whole watchdog interval.
invoke_loop() {
  if [ "${TEST_SHIM:-0}" = 1 ]; then
    node "${LOOP%/*}/run-fixall-loop.mjs"
  else
    "$LOOP"
  fi
}

run() {  # run <claude-exit> <queue-exit>   → $OUT (loop output), $CALLS (argv log), $STATUS
  : > "$CALLS"
  : > "$CLAUDE_PID_FILE"
  FIXALL_CAFFEINATE="$TMP/bin/caffeinate" \
  STUB_CLAUDE_SLEEP="${STUB_CLAUDE_SLEEP:-0}" \
  STUB_YIELD_EXIT="${STUB_YIELD_EXIT:-0}" \
  FIXALL_STALL_STATE="$TMP/stall.state" \
  FIXALL_RUN_STATE="$TMP/run-state" \
  FIXALL_FORCE=1 \
  FIXALL_TSX="$TMP/bin/tsx" \
  FIXALL_PROD_SYNC= \
  FIXALL_CLOSE_BUILT= \
  CLAUDE_BIN="${TEST_CLAUDE_BIN:-$TMP/bin/claude}" \
  FIXALL_MAX_MINUTES=1 \
  FIXALL_MAX_USD= \
  STUB_CLAUDE_EXIT="$1" \
  STUB_QUEUE_EXIT="$2" \
  invoke_loop > "$TMP/out.txt" 2>&1
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

# --- The run is held awake, for exactly as long as it lives (AITD-488) -------------
STUB_CLAUDE_SLEEP=0.3 run 0 0
called "the run is held awake while it lives" "caffeinate " "-i" "-w"
CAFF_PID=$(grep '^caffeinate ' "$CALLS" | head -1 | sed -n 's/.*-w \([0-9][0-9]*\).*/\1/p')
RUN_PID=$(cat "$CLAUDE_PID_FILE" 2>/dev/null)
if [ -n "$CAFF_PID" ] && [ "$CAFF_PID" = "$RUN_PID" ]; then ok
else bad "caffeinate names the run's OWN pid — as a wrapper it would take the kill the watchdog means for the run" \
         "caffeinate -w '$CAFF_PID', run pid '$RUN_PID'"; fi
if grep '^caffeinate ' "$CALLS" | grep -q -- ' -d'; then
  bad "no -d: the display may sleep, nobody is watching" "$(grep '^caffeinate ' "$CALLS")"
else ok; fi

# --- Stand down while someone is working this Mac (AITD-489) -----------------------
called "the loop asks whether to stand down, about OTHER sessions not itself" \
       "fixall-pause.ts" "yield" "--self-pid"
called "the loop takes its lock as --scheduled, so the two loops cannot pause each other" \
       "fixall-session.ts" "acquire" "--scheduled"

STUB_YIELD_EXIT=2 run 0 0
if echo "$OUT" | tail -1 | grep -q '^RESULT: SKIPPED'; then ok
else bad "a tick stands down while someone is working" "$OUT"; fi
if echo "$OUT" | grep -q "is working /w/web"; then ok
else bad "…and repeats the reason, so the log says who and where" "$OUT"; fi
not_called "^claude " "a paused tick must not start a session"

# Unreadable must RUN, not stall: until astrid-web lands the script it is absent,
# and a loop that stops for a missing file would be the worse outage.
STUB_YIELD_EXIT=1 run 0 0
if echo "$OUT" | grep -q "could not read the pause state"; then ok
else bad "an unreadable pause state is reported" "$OUT"; fi
called "…and the run still happens" "claude -p"

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
  # A bare origin, so the loop's end-of-run push has somewhere real to go.
  git init -q --bare -b main "$SANDBOX/origin.git"
  git remote add origin "$SANDBOX/origin.git"
  git push -q -u origin main
) >/dev/null 2>&1
sgit() { git -C "$SANDBOX/repo" "$@"; }

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
  FIXALL_PROD_SYNC= \
  FIXALL_CLOSE_BUILT= \
  CLAUDE_BIN="${1:-$TMP/bin/claude}" \
  FIXALL_MAX_MINUTES=1 \
  FIXALL_MAX_USD= \
  FIXALL_STALL_STATE="$STALL_STATE" \
  FIXALL_RUN_STATE="$TMP/sandbox-run-state" \
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

# Standing down for someone working this Mac is a skip like any other (AITD-489): a
# pause nobody lifts must announce itself, not skip every tick in silence.
rm -f "$STALL_STATE"
clean_sandbox
STUB_YIELD_EXIT=2 run_sandbox
not_called "post-list-message.ts" "the first stood-down tick stays quiet"
STUB_YIELD_EXIT=2 run_sandbox
STUB_YIELD_EXIT=2 run_sandbox
posted "the third stood-down tick in a row posts to the list chat (AITD-489)" "is working /w/web"
STUB_YIELD_EXIT=2 run_sandbox
not_called "post-list-message.ts" "…once per stand-down, not once per tick"
run_sandbox
STUB_YIELD_EXIT=2 run_sandbox
not_called "post-list-message.ts" "a tick that runs in between starts the count again"

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

# --- …and the tree is PUT BACK, so the next tick is not wedged on it -----------------
# astrid-web 2026-09-27: reporting the mess was not enough — every later tick skipped on
# it until a human came. The work is saved as a WIP commit (never on main) and HEAD
# returns to main.
if [ "$(sgit rev-parse --abbrev-ref HEAD)" = "main" ] && [ -z "$(sgit status --porcelain)" ]; then ok
else bad "a dirty run is put back on a clean main" "$(sgit status)"; fi
if [ "$(sgit log -1 --format=%s main)" = "init" ]; then ok
else bad "…without committing anything to main" "$(sgit log --oneline -3 main)"; fi
WIP=$(sgit branch -r --list 'origin/wip/fixall-ios-*' | tr -d ' ' | head -1)
if [ -n "$WIP" ] && sgit show "$WIP:leftover.txt" >/dev/null 2>&1 \
   && sgit log -1 --format=%s "$WIP" | grep -q "UNFINISHED, UNVERIFIED"; then ok
else bad "…the leftover work is pushed as a WIP commit on a wip/ branch" "$(sgit branch -a)"; fi
posted "…and the board is told where it went" "saved as an unverified WIP commit"
clean_sandbox

# A run the watchdog kills mid-task, on its task branch: the work lands on THAT branch.
cat > "$TMP/bin/claude-killed-mid-task" <<'STUB'
#!/bin/bash
echo "claude $*" >> "$CALLS"
git checkout -q -b fix/aitd-9-half-done
echo "half" > half.txt
exit 143
STUB
chmod +x "$TMP/bin/claude-killed-mid-task"
rm -f "$STALL_STATE"
run_sandbox "$TMP/bin/claude-killed-mid-task"
if echo "$OUT" | tail -1 | grep -q '^RESULT: FAILED — killed'; then ok
else bad "a killed run still reports FAILED" "$OUT"; fi
if [ "$(sgit rev-parse --abbrev-ref HEAD)" = "main" ] && [ -z "$(sgit status --porcelain)" ] \
   && sgit show origin/fix/aitd-9-half-done:half.txt >/dev/null 2>&1 \
   && sgit log -1 --format=%s origin/fix/aitd-9-half-done | grep -q "UNFINISHED"; then ok
else bad "a killed run's work is saved on its task branch, pushed, and HEAD is back on main" "$OUT
$(sgit branch -a)"; fi
posted "…and the board hears where its work went" "saved on \`fix/aitd-9-half-done\`"

# A run that committed its work but ended on its task branch: push it, go back to main.
cat > "$TMP/bin/claude-leaves-branch" <<'STUB'
#!/bin/bash
echo "claude $*" >> "$CALLS"
git checkout -q -b fix/aitd-10-done
echo "done" > done.txt
git add done.txt && git commit -q -m "fix: done"
exit 0
STUB
chmod +x "$TMP/bin/claude-leaves-branch"
run_sandbox "$TMP/bin/claude-leaves-branch"
if echo "$OUT" | tail -1 | grep -q '^RESULT: OK' && [ "$(sgit rev-parse --abbrev-ref HEAD)" = "main" ] \
   && sgit rev-parse -q --verify origin/fix/aitd-10-done >/dev/null; then ok
else bad "a clean task branch is pushed and the loop returns to main" "$OUT"; fi

# One task per scheduled run: the cap reaches the session.
cat > "$TMP/bin/claude-env" <<'STUB'
#!/bin/bash
echo "claude MAX_TASKS=$ASTRID_FIXALL_MAX_TASKS" >> "$CALLS"
exit 0
STUB
chmod +x "$TMP/bin/claude-env"
run_sandbox "$TMP/bin/claude-env"
if grep -q "claude MAX_TASKS=1" "$CALLS"; then ok
else bad "the session is told to take one task (ASTRID_FIXALL_MAX_TASKS=1)" "$(cat "$CALLS")"; fi
clean_sandbox

# --- A run that SAYS it failed is a failed run, whatever it exits (AITD-440) ---------
# 2026-09-27 08:30: the `astrid` MCP server timed out while the session was starting. The
# session reported "RESULT: FAILED — … never read the queue", but `claude -p` exited 0, so
# the loop wrote RESULT: OK under it, marked the wake keys seen, and told the board nothing.
# The run's own verdict is the better witness than its exit code.
cat > "$TMP/bin/claude-reports-failed" <<'STUB'
#!/bin/bash
echo "claude $*" >> "$CALLS"
echo "Tried to start."
echo "RESULT: FAILED — the astrid MCP server timed out after 30 seconds"
exit 0
STUB
chmod +x "$TMP/bin/claude-reports-failed"

rm -f "$STALL_STATE"
clean_sandbox
run_sandbox "$TMP/bin/claude-reports-failed"
if echo "$OUT" | tail -1 | grep -q '^RESULT: FAILED'; then ok
else bad "a run whose own RESULT: line says FAILED must not be logged OK" "$OUT"; fi
if [ "$STATUS" != 0 ]; then ok; else bad "…and the loop exits non-zero" "$OUT"; fi
called "…and its wake keys get a strike, not a mute" \
       "agent-queue-status.ts" "--mark-seen" "--failed"
posted "…and the board hears the run's own reason" "MCP server timed out"
if echo "$OUT" | grep -q '^RESULT: FAILED — the astrid MCP'; then ok
else bad "…and the run's own output still reaches the log" "$OUT"; fi

# Only the LAST RESULT: line counts: a run that quotes an old failure and then finishes
# is a finished run.
cat > "$TMP/bin/claude-recovers" <<'STUB'
#!/bin/bash
echo "claude $*" >> "$CALLS"
echo "RESULT: FAILED — first attempt"
echo "RESULT: OK — 1 task"
exit 0
STUB
chmod +x "$TMP/bin/claude-recovers"
run_sandbox "$TMP/bin/claude-recovers"
if echo "$OUT" | tail -1 | grep -q '^RESULT: OK'; then ok
else bad "a run whose LAST RESULT: line is OK is still OK" "$OUT"; fi
clean_sandbox

# --- The loop runs what is MERGED, not what someone last pulled (2026-09-27) ---------
# A merged loop fix sat unused here until a human pulled it. Each tick that passes the
# guards fast-forwards main; if the loop script itself changed, it restarts on the new one.
UPSTREAM="$TMP/upstream"
git clone -q "$SANDBOX/origin.git" "$UPSTREAM" 2>/dev/null
git -C "$UPSTREAM" config user.email t@example.com; git -C "$UPSTREAM" config user.name Test
push_upstream() {  # push_upstream <file> <line>
  echo "$2" >> "$UPSTREAM/$1"
  git -C "$UPSTREAM" pull -q --ff-only origin main 2>/dev/null
  git -C "$UPSTREAM" add -A && git -C "$UPSTREAM" commit -q -m "upstream: $1" && git -C "$UPSTREAM" push -q origin main 2>/dev/null
}
sgit fetch -q origin 2>/dev/null
push_upstream NOTES.md "merged elsewhere"
run_sandbox
if [ "$(sgit rev-parse HEAD)" = "$(git -C "$UPSTREAM" rev-parse HEAD)" ] && echo "$OUT" | grep -q "updated main"; then ok
else bad "a tick fast-forwards main to origin/main" "$OUT"; fi
if echo "$OUT" | grep -q "restarting"; then bad "…and does not restart when the loop itself did not change" "$OUT"; else ok; fi

push_upstream scripts/fixall-loop.sh "# a change to the loop itself"
run_sandbox
if echo "$OUT" | grep -q "restarting on the new version" \
   && [ "$(grep -c "restarting on the new version" "$TMP/out.txt")" = 1 ] \
   && echo "$OUT" | tail -1 | grep -q '^RESULT: OK'; then ok
else bad "a changed loop restarts itself once, on the new version, and finishes" "$OUT"; fi
if tail -1 "$SANDBOX/repo/scripts/fixall-loop.sh" | grep -q "a change to the loop itself"; then ok
else bad "…and the checkout now holds the new loop" "$(tail -2 "$SANDBOX/repo/scripts/fixall-loop.sh")"; fi
clean_sandbox

# --- Doing must not be a dead end (2026-09-28) ------------------------------------
# A claim whose run died sat in Doing forever. Each tick releases abandoned claims
# BEFORE deciding whether there is work, and each run's own claims are released after it.
cat > "$TMP/bin/claude-claims" <<'STUB'
#!/bin/bash
echo "claude CLAIMS=$ASTRID_FIXALL_CLAIMS_FILE" >> "$CALLS"
[ -n "$ASTRID_FIXALL_CLAIMS_FILE" ] && echo "AITD-7" >> "$ASTRID_FIXALL_CLAIMS_FILE"
exit 0
STUB
chmod +x "$TMP/bin/claude-claims"
run_sandbox "$TMP/bin/claude-claims"
STALE_LINE=$(grep -n "release-stuck-doing.ts --agent claude --list aa41c1a3" "$CALLS" | head -1 | cut -d: -f1)
QUEUE_LINE=$(grep -n "agent-queue-status.ts" "$CALLS" | grep -v mark-seen | head -1 | cut -d: -f1)
CLAUDE_LINE=$(grep -n "^claude CLAIMS=" "$CALLS" | head -1 | cut -d: -f1)
CLAIMS_LINE=$(grep -n "release-stuck-doing.ts --agent claude --claims-file" "$CALLS" | head -1 | cut -d: -f1)
if [ -n "$STALE_LINE" ] && [ -n "$QUEUE_LINE" ] && [ "$STALE_LINE" -lt "$QUEUE_LINE" ] \
   && grep "release-stuck-doing.ts --agent claude --list" "$CALLS" | grep -q -- "--stale-minutes 180"; then ok
else bad "abandoned Doing claims are released at tick start, before the queue check" "$(cat "$CALLS")"; fi
if grep -q "^claude CLAIMS=/" "$CALLS"; then ok
else bad "the session is given a claims file to record into" "$(cat "$CALLS")"; fi
if [ -n "$CLAIMS_LINE" ] && [ -n "$CLAUDE_LINE" ] && [ "$CLAIMS_LINE" -gt "$CLAUDE_LINE" ]; then ok
else bad "the run's own claims are released after it" "$(cat "$CALLS")"; fi
# Waiting must come back on its own: the preflight sweeps the iOS board's lanes.
if grep "agent-queue-status.ts" "$CALLS" | grep -v mark-seen | grep -q -- "--board ios"; then ok
else bad "the preflight sweeps the iOS lanes (--board ios), so due/unblocked Waiting tasks return" "$(cat "$CALLS")"; fi
PRS_LINE=$(grep -n "open-fixall-prs.ts --claims-file" "$CALLS" | head -1 | cut -d: -f1)
if [ -n "$PRS_LINE" ] && [ "$PRS_LINE" -gt "$CLAUDE_LINE" ] && [ "$PRS_LINE" -lt "$CLAIMS_LINE" ] \
   && grep "open-fixall-prs.ts" "$CALLS" | grep -q -- "--repo .*/sandbox/repo$"; then ok
else bad "completed work gets its PR opened after the run, against this repo, before claims are released" "$(cat "$CALLS")"; fi
clean_sandbox

# --- Apple lifecycle: bookkeeping is durable, not a success-shaped fallback --------
STUB_PR_EXIT=1 run 0 0
if [ "$STATUS" != 0 ] && echo "$OUT" | tail -1 | grep -q '^RESULT: FAILED'; then ok
else bad "Apple lifecycle: failed PR bookkeeping cannot report OK" "$OUT"; fi
not_called "--mark-seen" "failed bookkeeping must not acknowledge the wake"
if [ -f "$TMP/run-state/active/claims" ] && [ -f "$TMP/run-state/active/keys" ]; then ok
else bad "claims and exact wake keys survive a bookkeeping failure" "$OUT"; fi

# Recovery happens before even a quiet preflight; it does not pay for another agent.
run 0 3
called "pending bookkeeping is retried before a quiet tick" "open-fixall-prs.ts" "--claims-file"
called "recovery acknowledges the original exact wake keys" "--mark-seen" "--seen-keys" '["comment:c1","task:t1"]' "!--failed"
not_called "^claude " "recovery must not launch another agent on an empty queue"
if [ ! -d "$TMP/run-state/active" ]; then ok
else bad "successful recovery clears only its pending run" "$OUT"; fi

STUB_RELEASE_EXIT=1 run 0 0
not_called "--mark-seen" "failed claims recovery must not acknowledge the wake"
if [ "$STATUS" != 0 ]; then ok
else bad "claims recovery failure is a failed tick" "$OUT"; fi
run 0 3
called "failed claims recovery is retried next tick" "release-stuck-doing.ts" "--claims-file"
not_called "open-fixall-prs.ts" "successful PR bookkeeping is not repeated during recovery"

STUB_SEEN_EXIT=1 run 0 0
if [ "$STATUS" != 0 ] && [ -f "$TMP/run-state/active/keys" ]; then ok
else bad "wake acknowledgement failure is reported and preserves its keys" "$OUT"; fi
run 0 3
called "failed wake acknowledgement is retried" "--mark-seen" '["comment:c1","task:t1"]'

# A crash before recording an outcome defaults to failure, never a success ack.
mkdir -p "$TMP/run-state/active"
printf '%s\n' '["comment:interrupted"]' > "$TMP/run-state/active/keys"
: > "$TMP/run-state/active/claims"
run 0 3
called "an interrupted run strikes its original wake key" "--mark-seen" "--failed" '["comment:interrupted"]'
not_called "^claude " "interrupted-run bookkeeping needs no new agent"

# Tooling may live anywhere on the dedicated Apple machine, not beside this worktree.
mkdir -p "$TMP/shared-tooling"
ASTRID_WEB_DIR="$TMP/shared-tooling" run 0 3
called "shared tooling override is used from the iOS working-tree lock" "$TMP/shared-tooling/scripts/fixall-session.ts"

# Ready may be empty while inbox replies still wake the existing intake.
STUB_QUEUE_LINE="QUEUE: no Ready tasks; one inbox reply for claude" run 0 0
called "mailbox wake uses the same board-scoped Claude intake" "agent-queue-status.ts" "--agent claude" "--board ios" "--no-write-seen"
called "an inbox-only preflight wakes the agent" "claude -p /fixall"

# A surviving child owns the pending run, even if the wrapper is gone.
mkdir -p "$TMP/run-state/active"
echo "$$" > "$TMP/run-state/active/child.pid"
printf '%s\n' '["comment:still-running"]' > "$TMP/run-state/active/keys"
: > "$TMP/run-state/active/claims"
run 0 0
not_called "^claude " "a pending live agent prevents a duplicate run"
not_called "--mark-seen" "a live agent's wake keys remain unacknowledged"
rm -f "$TMP/run-state/active/child.pid"
run 0 3
called "recovery proceeds once the old child is gone" "--mark-seen" "--failed" '["comment:still-running"]'

mkdir -p "$TMP/run-state/active"
echo "$$" > "$TMP/run-state/active/child.pid"
echo "before this boot" > "$TMP/run-state/active/child.started"
printf '%s\n' '["comment:reused-pid"]' > "$TMP/run-state/active/keys"
: > "$TMP/run-state/active/claims"
run 0 3
called "a reused PID after reboot does not strand recovery" "--mark-seen" "--failed" '["comment:reused-pid"]'
not_called "^claude " "PID-reuse recovery does not launch an unnecessary agent"

# TERM must stop the whole workload before unlocking, not orphan a build/test process.
export SIGNAL_LAUNCHER_PID="$TMP/signal-launcher.pid"
export SIGNAL_DESCENDANT_PID="$TMP/signal-descendant.pid"
cat > "$TMP/bin/claude-signal" <<'STUB'
#!/bin/bash
echo "claude $*" >> "$CALLS"
echo "$PPID" > "$SIGNAL_LAUNCHER_PID"
trap 'exit 0' TERM
bash -c 'trap "" TERM; while :; do sleep 1; done' &
echo "$!" > "$SIGNAL_DESCENDANT_PID"
wait
STUB
chmod +x "$TMP/bin/claude-signal"
for SIGNAL_MODE in direct shim; do
rm -f "$SIGNAL_LAUNCHER_PID" "$SIGNAL_DESCENDANT_PID"
TEST_SHIM=0
[ "$SIGNAL_MODE" != shim ] || TEST_SHIM=1
TEST_CLAUDE_BIN="$TMP/bin/claude-signal" FIXALL_KILL_GRACE_SECONDS=1 run 0 0 &
SIGNAL_TEST_PID=$!
for attempt in $(seq 1 100); do
  [ -s "$SIGNAL_DESCENDANT_PID" ] && break
  sleep 0.05
done
if [ -s "$SIGNAL_DESCENDANT_PID" ]; then
  TARGET_PID=$(cat "$SIGNAL_LAUNCHER_PID")
  if [ "$SIGNAL_MODE" = shim ]; then
    TARGET_PID=$(ps -p "$TARGET_PID" -o ppid= | tr -d ' ')
  fi
  kill -TERM "$TARGET_PID"
else
  bad "signal regression agent started"
fi
wait "$SIGNAL_TEST_PID"
OUT=$(cat "$TMP/out.txt")
called "TERM records a failed wake, not a successful acknowledgement" "--mark-seen" "--failed"
DESCENDANT_STATE=$(ps -p "$(cat "$SIGNAL_DESCENDANT_PID")" -o stat= 2>/dev/null || true)
case "$DESCENDANT_STATE" in
  ""|*Z*) ok ;;
  *) bad "TERM stops even a descendant that ignores TERM" "$DESCENDANT_STATE" ;;
esac
if echo "$OUT" | tail -1 | grep -q '^RESULT: FAILED — launcher interrupted'; then ok
else bad "TERM completes recovery and reports interruption" "$OUT"; fi
SEEN_LINE=$(grep -n -- "--mark-seen" "$CALLS" | tail -1 | cut -d: -f1)
UNLOCK_LINE=$(grep -n "fixall-session.ts release" "$CALLS" | tail -1 | cut -d: -f1)
if [ -n "$SEEN_LINE" ] && [ -n "$UNLOCK_LINE" ] && [ "$SEEN_LINE" -lt "$UNLOCK_LINE" ]; then ok
else bad "interruption keeps the tree lock until bookkeeping finishes" "$(cat "$CALLS")"; fi
done
unset TEST_SHIM

# Exercise the real one-minute watchdog, including its escalation grace. The agent
# exits 0 on TERM while its child ignores it: neither is a finished run, and stopping
# the watchdog too early orphans the child.
TEST_CLAUDE_BIN="$TMP/bin/claude-signal" FIXALL_KILL_GRACE_SECONDS=1 run 0 0
DESCENDANT_STATE=$(ps -p "$(cat "$SIGNAL_DESCENDANT_PID")" -o stat= 2>/dev/null || true)
case "$DESCENDANT_STATE" in
  ""|*Z*) ok ;;
  *) bad "watchdog finishes escalation before releasing the tree" "$DESCENDANT_STATE" ;;
esac
called "watchdog strikes the wake keys" "--mark-seen" "--failed"
if echo "$OUT" | tail -1 | grep -q '^RESULT: FAILED — killed after 1m'; then ok
else bad "watchdog timeout reports failure after descendant cleanup" "$OUT"; fi

# Abrupt wrapper death also leaves clean-start provenance for WIP recovery next tick.
mkdir -p "$TMP/sandbox-run-state/active"
printf '%s\n' '["comment:crashed"]' > "$TMP/sandbox-run-state/active/keys"
: > "$TMP/sandbox-run-state/active/claims"
: > "$TMP/sandbox-run-state/active/guard-clean"
dirty_sandbox
run_sandbox
if [ -z "$(sgit status --porcelain)" ] && [ "$(sgit branch --show-current)" = main ]; then ok
else bad "an interrupted clean-start run saves WIP before the dirty-tree guard" "$OUT"; fi
called "abrupt interruption strikes its saved exact key" "--mark-seen" "--failed" '["comment:crashed"]'
posted "abrupt interruption is reported on the board" "recovered an interrupted run"

# A failed push must retain the branch/journal and retry, not claim a clean handoff.
sgit remote set-url --push origin "$TMP/missing-origin"
run_sandbox "$TMP/bin/claude-leaves-mess"
if [ "$STATUS" != 0 ] && [ -d "$TMP/sandbox-run-state/active" ] \
   && [ "$(sgit branch --show-current)" != main ]; then ok
else bad "failed WIP push retains both branch and journal" "$OUT"; fi
not_called "--mark-seen" "failed WIP push does not acknowledge its wake"
sgit remote set-url --push origin "$SANDBOX/origin.git"
run_sandbox
if [ "$(sgit branch --show-current)" = main ] && [ ! -d "$TMP/sandbox-run-state/active" ]; then ok
else bad "next tick completes the failed WIP push before new work" "$OUT"; fi
called "failed WIP run is acknowledged as failed after recovery" "--mark-seen" "--failed"

# Once the checkout was restored, later human edits do not belong to that run.
STUB_PR_EXIT=1 run_sandbox
dirty_sandbox
run_sandbox
if [ -f "$SANDBOX/repo/work-in-progress.txt" ] && [ -n "$(sgit status --porcelain)" ] \
   && [ "$(sgit branch --show-current)" = main ]; then ok
else bad "bookkeeping retry does not scoop later human edits into WIP" "$OUT"; fi
not_called "^claude " "later human edits still trigger the dirty-tree guard"
clean_sandbox

echo ""
if [ "$FAIL" = 0 ]; then echo "✓ fixall-loop: $PASS checks passed"; exit 0; fi
echo "✗ fixall-loop: $FAIL failed, $PASS passed"; exit 1
