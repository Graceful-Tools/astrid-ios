#!/bin/zsh -l
#
# fixall-loop.sh — one scheduled, unattended pass of /fixall.
#
# launchd calls this every half hour through scripts/run-fixall-loop.mjs (the node
# shim exists for a TCC reason — read the top of that file before "simplifying" it).
# You can also run it by hand to test the guards:
#
#   npm run fixall:loop
#
# The last line is always exactly one RESULT: line, like monkey-weekly.sh and the
# weekly deep review, so a scheduler or a person skimming the log can tell what
# happened without reading it.
#
#   RESULT: OK      — a run happened
#   RESULT: SKIPPED — deliberately did nothing, and why
#   RESULT: FAILED  — tried and could not
#
# WHY A SKIP IS THE COMMON CASE. Every half hour is often, and most ticks have
# nothing to do or land while someone is already working the tree. A skip is the
# healthy outcome, not an error, so it exits 0 and says so in one line.
#
# Environment:
#   FIXALL_MODEL        model for the unattended run (default: opus)
#   FIXALL_MAX_MINUTES  watchdog, kills a wedged run (default: 75)
#   FIXALL_MAX_USD      hard spend cap for one run (default: 10; empty = no cap)
#   CLAUDE_BIN          path to the claude CLI (default: ~/.local/bin/claude)
#   FIXALL_FORCE=1      skip the dirty-tree/branch guard (testing only)
#   FIXALL_TSX          path to tsx (default: astrid-web's). scripts/test-fixall-loop.sh
#                       points it at a stub so the test can run this loop for real without
#                       taking the working-tree lock or calling the board.
#   FIXALL_CAFFEINATE   caffeinate binary that holds the Mac awake for the run
#                       (default: caffeinate; empty = do not assert, as the test does)
#   FIXALL_STALL_STATE  where the consecutive-skip count lives (default: beside the log)
#   FIXALL_STALL_ALERT_AFTER  how many skips in a row before saying so (default: 3)
#   FIXALL_PROD_SYNC    the ios-prod/mac-prod sync run each tick (default:
#                       scripts/sync-prod-branches.sh; empty = skip, as the test does)
#   FIXALL_CLOSE_BUILT  closes Doing tasks whose TestFlight build is VALID (default:
#                       node scripts/close-built-tasks.mjs; empty = skip, as the test does)
#   ASTRID_WEB_DIR      shared task tooling checkout (default: sibling astrid-web)
#   FIXALL_RUN_STATE    durable per-checkout run state (default: under ~/Library/Application
#                       Support/Astrid; never in node_modules or a temporary directory)
#   FIXALL_KILL_GRACE_SECONDS  grace before escalating a stopped process tree (default: 5)

set -u
export PATH="/opt/homebrew/bin:$PATH"

REPO="${0:A:h:h}"
WEB="${ASTRID_WEB_DIR:-$REPO/../astrid-web}"
export ASTRID_WEB_DIR="$WEB"
TSX="${FIXALL_TSX:-$WEB/node_modules/.bin/tsx}"
CLAUDE="${CLAUDE_BIN:-$HOME/.local/bin/claude}"
MODEL="${FIXALL_MODEL:-opus}"
# 75, not 50: on 2026-09-27 astrid-web's loop, capped at ONE task, still hit a 50m
# watchdog. A killed run is now saved and harmless, but a task that never fits
# would be killed on every attempt.
MAX_MINUTES="${FIXALL_MAX_MINUTES:-75}"
MAX_USD="${FIXALL_MAX_USD-10}"
IOS_LIST_ID="aa41c1a3-bd63-4c6d-9b87-42c6e0aafa36"
STALL_STATE="${FIXALL_STALL_STATE:-$HOME/Library/Logs/astrid-fixall-stall.state}"
STALL_ALERT_AFTER="${FIXALL_STALL_ALERT_AFTER:-3}"
PROD_SYNC="${FIXALL_PROD_SYNC-$REPO/scripts/sync-prod-branches.sh}"
CLOSE_BUILT="${FIXALL_CLOSE_BUILT-node $REPO/scripts/close-built-tasks.mjs}"
RUN_STATE="${FIXALL_RUN_STATE:-$HOME/Library/Application Support/Astrid/fixall-ios/$(printf '%s' "$REPO" | cksum | awk '{print $1}')}"
ACTIVE_RUN="$RUN_STATE/active"
KILL_GRACE="${FIXALL_KILL_GRACE_SECONDS:-5}"
if [[ "$MAX_MINUTES" != <-> ]] || [ "$MAX_MINUTES" -eq 0 ] || [[ "$KILL_GRACE" != <-> ]]; then
  echo "RESULT: FAILED — watchdog minutes must be positive and kill grace must be nonnegative integers"
  exit 1
fi

echo "──────── fixall loop $(date '+%Y-%m-%d %H:%M:%S') ────────"

cd "$REPO" || { echo "RESULT: FAILED — cannot enter $REPO"; exit 1; }
if [ ! -d "$WEB" ]; then
  echo "RESULT: FAILED — no shared tooling checkout at $WEB (set ASTRID_WEB_DIR)"
  exit 1
fi

# Post run-level news where Jon actually reads it. Per-task detail is already on
# the tasks as comments; this is only for the things no task owns — a crash, a
# wedged run — which is exactly the case where the agent cannot report for itself.
post_to_list() {
  [ -x "$TSX" ] || return 0
  ( cd "$WEB" && "$TSX" scripts/post-list-message.ts "$IOS_LIST_ID" "$1" ) \
    >/dev/null 2>&1 || echo "  (could not post to list chat)"
}

# ── The stall alarm ──────────────────────────────────────────────────────────
# The tree guards below are RIGHT to refuse once. What they must not do is refuse
# silently and indefinitely: on 2026-09-22 a run left four files uncommitted on a
# branch, and guard 2 then skipped 25 consecutive ticks across 12 hours with the
# queue non-empty the whole time. The only trace was a line in a log nobody reads
# unless they already suspect a problem, so Jon found out by asking (AITD-426).
#
# The skip is not the defect. The silence is. So: count consecutive skips and, on
# the Nth, say so ONCE — once per stall, not once per tick, because at two ticks
# an hour a per-tick alert is just a slower way of being ignored. Any tick that
# gets past the guards clears the count, so the next stall is heard too.
#
# State is one line: <count> <alerted 0|1> <first-skip ISO8601>.
stall_field() {  # stall_field <1-based field>  → value, or 0/empty
  [ -f "$STALL_STATE" ] || { echo ""; return 0; }
  awk -v f="$1" 'NR==1 { print $f }' "$STALL_STATE" 2>/dev/null
}

clear_stall() { rm -f "$STALL_STATE" 2>/dev/null; return 0; }

# Every exit path out of the guards goes through here, so a new guard cannot be
# added without deciding what its stall looks like.
skip_and_maybe_alert() {  # skip_and_maybe_alert <one-line reason> <detail block>
  local reason="$1" detail="${2:-}"
  local count alerted since
  count=$(stall_field 1); count=$(( ${count:-0} + 1 ))
  alerted=$(stall_field 2); alerted=${alerted:-0}
  since=$(stall_field 3)
  [ -n "$since" ] || since=$(date -u '+%Y-%m-%dT%H:%M:%SZ')

  if [ "$count" -ge "$STALL_ALERT_AFTER" ] && [ "$alerted" != "1" ]; then
    # Only now — once per stall — is it worth an HTTP request to say whether
    # anything is actually piling up behind the stall. That is what makes this
    # worth interrupting someone for, rather than a tidy-up note.
    local queue
    queue=$( cd "$WEB" && "$TSX" scripts/agent-queue-status.ts \
               --agent claude --list "$IOS_LIST_ID" --include-unassigned --no-write-seen 2>&1 \
             | grep -E '^QUEUE:' | head -1 )
    [ -n "$queue" ] || queue="QUEUE: could not tell"
    post_to_list "## Scheduled /fixall has been skipping

$reason

It has skipped **$count ticks in a row**, first at \`$since\`. That guard is doing its job, but it will keep refusing until what is in its way is cleared, so this says so once rather than waiting to be asked.

$detail

$queue

Log: \`~/Library/Logs/astrid-fixall.log\`"
    alerted=1
  fi

  echo "$count $alerted $since" > "$STALL_STATE" 2>/dev/null
  echo "RESULT: SKIPPED — $reason"
}

# ── Before the guards: keep ios-prod / mac-prod on what the App Store serves ──
# (AITD-434 / AITD-435.) Every tick, even one that skips below: it moves refs on the remote and
# never touches the working tree, so a busy or dirty checkout is no reason to let the branches
# fall behind a release. A tick with no new release pushes nothing. Never fatal to the loop.
if [ -n "$PROD_SYNC" ] && [ -x "$PROD_SYNC" ]; then
  "$PROD_SYNC" 2>&1 | sed 's/^/  prod: /'
fi

# ── Before the guards: close the tasks whose build is ready ──────────────────
# A task stays in Doing until a VALID TestFlight build carries its fix, and closing it used to
# be a step inside a session — which the empty-queue skip below never starts. So on a quiet
# board nothing came back for them and Doing filled up (Jon, 2026-09-27). Every tick, like the
# prod sync: it reads the board and App Store Connect and never touches the working tree.
# Never fatal to the loop.
if [ -n "$CLOSE_BUILT" ]; then
  ${=CLOSE_BUILT} 2>&1 | sed 's/^/  /'
fi

# ── Guard 1: one session per working tree ────────────────────────────────────
# Cheap by design: no Claude session is started just to discover the tree is
# busy. Also backs off correctly when Jon is running /fixall interactively.
#
# Run it FROM the iOS checkout. The lock keys on `git rev-parse
# --absolute-git-dir` of the cwd, so a `cd ../astrid-web` first would lock the
# WEB tree, leave this one unguarded, and exit 0 as though it had worked.
if [ ! -x "$TSX" ]; then
  echo "RESULT: FAILED — no tsx at $TSX (astrid-web checkout missing or not installed)"
  exit 1
fi

"$TSX" "$WEB/scripts/fixall-session.ts" acquire --pid $$ --harness claude-code --scheduled
LOCK_STATUS=$?
if [ "$LOCK_STATUS" -eq 2 ]; then
  echo "RESULT: SKIPPED — another live session holds this checkout"
  exit 0
elif [ "$LOCK_STATUS" -ne 0 ]; then
  echo "RESULT: FAILED — could not take the working-tree lock (exit $LOCK_STATUS)"
  exit 1
fi

release_lock() {
  "$TSX" "$WEB/scripts/fixall-session.ts" release --pid $$ >/dev/null 2>&1
}
trap release_lock EXIT

# One pending run per locked checkout. Each successful phase gets its own receipt, so
# repairing a failed acknowledgement never re-runs an agent or re-releases its claims.
finalize_run() {
  local result
  if [ ! -f "$ACTIVE_RUN/prs-done" ]; then
    local pr_out
    pr_out=$( cd "$WEB" && "$TSX" scripts/open-fixall-prs.ts --claims-file "$ACTIVE_RUN/claims" --repo "$REPO" 2>&1 )
    result=$?
    [ -n "$pr_out" ] && echo "$pr_out"
    # 3 = the run's work is pushed but a PR could not be opened (expired gh login, no commits
    # between branches). That needs a human, not a retry: retrying it every tick wedged the
    # worker in recovery and kept the run's claims in Doing (AITD-559). 1 = a crash, retried.
    if [ "$result" -eq 3 ]; then
      post_to_list "**Scheduled /fixall finished work but could not open its PR** — open it by hand so it gets reviewed:

$(echo "$pr_out" | grep 'PR: FAILED')"
    elif [ "$result" -ne 0 ]; then
      return "$result"
    fi
    touch "$ACTIVE_RUN/prs-done" || return 1
  fi
  if [ ! -f "$ACTIVE_RUN/claims-released" ]; then
    ( cd "$WEB" && "$TSX" scripts/release-stuck-doing.ts --agent claude --claims-file "$ACTIVE_RUN/claims" --repo "$REPO" )
    result=$?
    [ "$result" -eq 0 ] || return "$result"
    touch "$ACTIVE_RUN/claims-released" || return 1
  fi
  if [ ! -f "$ACTIVE_RUN/wake-recorded" ]; then
    local keys outcome=failed
    keys=$(cat "$ACTIVE_RUN/keys") || return 1
    [ ! -f "$ACTIVE_RUN/outcome" ] || outcome=$(cat "$ACTIVE_RUN/outcome")
    local -a failed_args
    failed_args=()
    [ "$outcome" = "finished" ] || failed_args=(--failed)
    if [ -n "$keys" ]; then
      ( cd "$WEB" && "$TSX" scripts/agent-queue-status.ts --agent claude --list "$IOS_LIST_ID" \
          --mark-seen "${failed_args[@]}" --seen-keys "$keys" ) || return 1
    fi
    touch "$ACTIVE_RUN/wake-recorded" || return 1
  fi
  rm -f "$ACTIVE_RUN/claims" "$ACTIVE_RUN/keys" "$ACTIVE_RUN/outcome" "$ACTIVE_RUN/run.out" \
    "$ACTIVE_RUN/child.pid" "$ACTIVE_RUN/child.started" "$ACTIVE_RUN/guard-clean" "$ACTIVE_RUN/prs-done" \
    "$ACTIVE_RUN/claims-released" "$ACTIVE_RUN/wake-recorded" "$ACTIVE_RUN/watchdog-fired" || return 1
  rmdir "$ACTIVE_RUN"
}

# This runs only for a checkout proven clean before the agent started. Never put WIP
# on main; retain it on its own branch before allowing the next tick to claim work.
restore_checkout() {
  local end_branch dirty_after
  end_branch=$(git rev-parse --abbrev-ref HEAD) || return 1
  dirty_after=$(git status --porcelain) || return 1
  if [ -n "$dirty_after" ]; then
    LEFT_DIRTY="$dirty_after"
    if [ "$end_branch" = "main" ] || [ "$end_branch" = "HEAD" ]; then
      end_branch="wip/fixall-ios-$(date +%Y%m%d-%H%M%S)-$$"
      git checkout -q -b "$end_branch" || return 1
    fi
    git add -A && git commit -q --no-verify -m "wip: scheduled /fixall run ended mid-task — UNFINISHED, UNVERIFIED

Saved by scripts/fixall-loop.sh so the checkout can return to main.
The build and tests have not been run on this. Continue from here; do not ship it." || return 1
    SAVED_BRANCH="$end_branch"
    echo "  run left uncommitted changes — saved as a WIP commit on $end_branch"
  fi
  if [ "$end_branch" != "main" ]; then
    git push -q -u origin "$end_branch" || return 1
    echo "  run left $end_branch — pushed it to origin for review"
    git checkout -q main || return 1
    echo "  returned to main from $end_branch"
  fi
  rm -f "$ACTIVE_RUN/guard-clean"
}

LEFT_DIRTY=""
SAVED_BRANCH=""
if [ -d "$ACTIVE_RUN" ]; then
  OLD_CHILD=$(cat "$ACTIVE_RUN/child.pid" 2>/dev/null)
  OLD_STARTED=$(cat "$ACTIVE_RUN/child.started" 2>/dev/null)
  if [[ "$OLD_CHILD" == <-> ]] && kill -0 "$OLD_CHILD" 2>/dev/null \
     && { [ -z "$OLD_STARTED" ] || [ "$OLD_STARTED" = "$(ps -p "$OLD_CHILD" -o lstart= 2>/dev/null)" ]; }; then
    echo "RESULT: SKIPPED — previous agent process $OLD_CHILD is still alive; retaining its recovery state"
    exit 0
  fi
  echo "  recovering interrupted /fixall bookkeeping from $ACTIVE_RUN"
  if { [ -f "$ACTIVE_RUN/guard-clean" ] && ! restore_checkout; } || ! finalize_run; then
    post_to_list "**Scheduled /fixall recovery failed** — work and wake keys are retained in \`$ACTIVE_RUN\`. No new agent was started. Check the Apple host log before retrying."
    echo "RESULT: FAILED — could not recover the previous run; durable state retained"
    exit 1
  fi
  post_to_list "**Scheduled /fixall recovered an interrupted run** — unfinished claims and wake keys were reconciled before checking for new work.${SAVED_BRANCH:+ Unverified work was saved on \`$SAVED_BRANCH\`.}"
fi

# The lock is held by THIS script, whose pid the agent cannot see. Inside
# `claude -p`, $PPID is the claude process — a different LIVE pid — so the
# agent's own `acquire` would return 2 and it would stop before reading the
# queue. fixall.md checks this variable and skips the acquire when it is set.
export ASTRID_FIXALL_LOCK_HELD=1
# One Ready task per run (docs/FIXALL_WORKFLOW.md → *One task per scheduled run*).
# A run that takes the whole queue does not fit the watchdog; the next tick takes
# the next task. Same rule as astrid-web/scripts/fixall-loop.sh.
export ASTRID_FIXALL_MAX_TASKS="${FIXALL_MAX_TASKS:-1}"

# ── Guard 1b: stand down while someone is working ────────────────────────────
# The lock above is per WORKING TREE; contention is per MACHINE. On 2026-10-11 a
# session worked astrid-web while this loop ran a simulator suite and the web
# loop ran predeploy: the 5-minute load average peaked over 890, and two web
# runs that day went red on test timeouts in files that pass alone, filing
# failure tasks for nothing. A simulator suite buries this Mac for the web
# loop's predeploy just as thoroughly as the other way round (AITD-489, after
# astrid-web's AWTD-1212).
#
# So an interactive `fixall-session.ts acquire` in EITHER repo stands both loops
# down, for as long as that session lives, and `npm run fixall:pause` in
# astrid-web covers the work no session knows about — plain Xcode, a manual
# build. `--scheduled` above is what keeps the two loops from pausing each
# other: they register as lock holders without publishing a pause.
#
# An unreadable pause state RUNS the tick and says so. Until the astrid-web
# change lands this script is simply absent, which is that case: the loop goes
# on exactly as it does today rather than stalling on a missing file.
YIELD_OUT=$("$TSX" "$WEB/scripts/fixall-pause.ts" yield --self-pid $$ 2>&1)
YIELD_STATUS=$?
if [ "$YIELD_STATUS" -eq 2 ]; then
  # Through the stall tracker, so a pause nobody lifts is announced on the board
  # like any other long skip rather than skipping every tick in silence.
  skip_and_maybe_alert "$YIELD_OUT" \
    "Standing down is deliberate while someone is working this Mac. If nobody is, \`npm run fixall:pause -- status\` in astrid-web says what is holding it, and \`npm run fixall:resume\` lifts an explicit pause."
  exit 0
elif [ "$YIELD_STATUS" -ne 0 ]; then
  echo "  ⚠️  could not read the pause state, running anyway: $YIELD_OUT"
fi

# ── Guard 2: never clobber work in progress ──────────────────────────────────
# /fixstuff takes no lock, so an interactive session editing files here is
# invisible to guard 1. This is the only thing between a 30-minute tick and
# uncommitted work.
GUARDS_CONFIRMED_CLEAN=0
if [ "${FIXALL_FORCE:-0}" != "1" ]; then
  BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
  DIRTY=$(git status --porcelain 2>/dev/null)
  if [ -n "$DIRTY" ]; then
    skip_and_maybe_alert "working tree is dirty, leaving it alone" \
      "On branch \`$BRANCH\`, uncommitted:

\`\`\`
$(echo "$DIRTY" | head -20)
\`\`\`"
    exit 0
  fi
  if [ "$BRANCH" != "main" ]; then
    skip_and_maybe_alert "HEAD is on $BRANCH, not main" \
      "The tree is clean but parked on \`$BRANCH\`. Merging it to \`main\` (or checking \`main\` out) starts the ticks again."
    exit 0
  fi
  GUARDS_CONFIRMED_CLEAN=1
fi

# Got past them: whatever the last stall was, it is over.
clear_stall

# ── Run what is merged, not what someone last pulled by hand ─────────────────
# Nothing else updates this checkout. On 2026-09-27 a merged loop fix sat unused
# in astrid-ios until a human pulled it. The guards above have just confirmed a
# clean tree on main, so a fast-forward cannot clobber anything. If the loop
# script itself changed, exec the new version: same pid, so the lock is simply
# reacquired, and FIXALL_SELF_UPDATED stops it updating twice. A failed fetch
# (offline, auth) degrades to running the current checkout — it must not become
# a loop that never runs. fsmonitor off: a stuck daemon hung a pull here.
if [ "$GUARDS_CONFIRMED_CLEAN" -eq 1 ] && [ "${FIXALL_SELF_UPDATED:-0}" != "1" ]; then
  BEFORE=$(git rev-parse HEAD)
  if GIT_TERMINAL_PROMPT=0 git -c core.fsmonitor=false fetch -q origin main 2>/dev/null \
     && git -c core.fsmonitor=false merge -q --ff-only origin/main 2>/dev/null; then
    AFTER=$(git rev-parse HEAD)
    if [ "$BEFORE" != "$AFTER" ]; then
      echo "  updated main $(git rev-parse --short "$BEFORE") → $(git rev-parse --short "$AFTER")"
      if ! git diff --quiet "$BEFORE" "$AFTER" -- scripts/fixall-loop.sh; then
        echo "  the loop changed — restarting on the new version"
        FIXALL_SELF_UPDATED=1 exec "$0" "$@"
      fi
    fi
  else
    echo "  ⚠️  could not fast-forward main to origin/main — running on $(git rev-parse --short HEAD)"
  fi
fi

# ── Doing must not be a dead end ─────────────────────────────────────────────
# The queue never takes Doing, so a claim whose session died sat there forever
# (astrid-web, 2026-09-28: three tasks, work on pushed branches, "not in Ready"
# every tick). A claim idle for FIXALL_STALE_DOING_MINUTES (default 180, well past
# the watchdog) goes back to Ready naming its branch; a second release hands it
# back to a human. Before guard 3, so a released task is work for this tick. Runs
# from astrid-web like every other board script; never fatal.
( cd "$WEB" && "$TSX" scripts/release-stuck-doing.ts --agent claude --list "$IOS_LIST_ID" \
    --stale-minutes "${FIXALL_STALE_DOING_MINUTES:-180}" --repo "$REPO" 2>&1 ) | sed 's/^/ /'

# ── Guard 3: is there actually any work? ─────────────────────────────────────
# THE expensive question, asked the cheap way. Without this a quiet tick still
# boots a whole session — CLAUDE.md, fixall.md, the MCP tool schemas — to call
# get_agent_queue once and find `empty: true`. At two ticks an hour that is most
# of a day's tokens spent learning there was nothing to do. GET
# /api/v1/agent-queue is the same question for one HTTP request.
#
# The seen-file write is the SECOND phase of waking. This preflight runs with
# --no-write-seen and hands its keys back on a KEYS: line; the run's outcome
# records them. A run that crashes, is watchdog-killed, or exhausts its budget
# must not mute the items that woke it on the first failure — otherwise "one run
# per item" becomes "one attempt ever" — but it gets a strike (--mark-seen
# --failed), and a key out of strikes is muted like a finished one, so a run that
# keeps dying on the same item cannot wake a session every tick forever. The
# strike limit lives in astrid-web/scripts/lib/wake-keys.ts; this loop only
# passes flags.
#
# Exit 1 means "could not tell" (network, auth) and must NOT be read as empty:
# a queue we cannot see is a reason to run and let the agent report properly,
# not a reason to skip quietly forever.
#
# `--board ios` runs the lane sweep first (astrid-web/scripts/ready-tasks.ts, as
# claude-code): a Waiting task whose date arrived or whose blockers are done goes
# back to Ready, and RECHECK/REVIEW items count as work. Without it — until
# 2026-09-30 — the iOS board was never swept: nothing parked in Waiting ever came
# back on its own, and the RECHECK/REVIEW work fixall.md asks for never surfaced.
QUEUE_OUT=$( cd "$WEB" && "$TSX" scripts/agent-queue-status.ts --agent claude --list "$IOS_LIST_ID" --board ios --include-unassigned --no-write-seen 2>&1 )
QUEUE_STATUS=$?
QUEUE_LINES=$(echo "$QUEUE_OUT" | grep -E '^(QUEUE|LANES|SEEN):')
QUEUE_KEYS=$(echo "$QUEUE_OUT" | sed -n 's/^KEYS: //p' | head -1)
echo "${QUEUE_LINES:-QUEUE: no verdict}" | sed 's/^/  /'
if [ "$QUEUE_STATUS" -eq 3 ]; then
  echo "RESULT: SKIPPED — nothing queued for claude"
  exit 0
fi

if [ ! -x "$CLAUDE" ]; then
  echo "RESULT: FAILED — no claude CLI at $CLAUDE (set CLAUDE_BIN)"
  exit 1
fi

# ── The run ──────────────────────────────────────────────────────────────────
# Two bounds, because a run goes wrong in two different ways.
#
# The watchdog catches one that HANGS. launchd will not start a second copy of a
# label while the first is alive, so one wedged run silently swallows every
# later tick until someone notices. macOS ships no `timeout`, hence the subshell.
#
# The budget catches one that stays BUSY — a task it cannot finish, retried
# until the clock runs out — which the watchdog would not stop for the whole window.
# --max-budget-usd only works with -p, which is the mode this always runs in.
BUDGET_ARGS=()
[ -n "$MAX_USD" ] && BUDGET_ARGS=(--max-budget-usd "$MAX_USD")

# Keep claims, output and exact wake keys through wrapper crashes/reboots. A missing
# outcome is a failed run; only verified completion may turn it into "finished".
umask 077
if ! mkdir -p "$RUN_STATE" || ! mkdir "$ACTIVE_RUN" \
   || ! printf '%s\n' "${QUEUE_KEYS:-}" > "$ACTIVE_RUN/keys" \
   || ! touch "$ACTIVE_RUN/claims" \
   || { [ "$GUARDS_CONFIRMED_CLEAN" -eq 1 ] && ! touch "$ACTIVE_RUN/guard-clean"; }; then
  echo "RESULT: FAILED — cannot prepare durable run state at $ACTIVE_RUN"
  exit 1
fi
RUN_OUT="$ACTIVE_RUN/run.out"
CLAIMS_FILE="$ACTIVE_RUN/claims"
export ASTRID_FIXALL_CLAIMS_FILE="$CLAIMS_FILE"

# Snapshot the tree before sending TERM: children may be reparented when their
# parent exits. Escalation targets only these specific pids, never process names.
stop_run() {
  local -a pids
  pids=("${(@f)$(process_tree "$CLAUDE_PID")}")
  local pid
  for pid in "${pids[@]}"; do kill -TERM "$pid" 2>/dev/null || true; done
  sleep "$KILL_GRACE"
  for pid in "${pids[@]}"; do kill -KILL "$pid" 2>/dev/null || true; done
}

process_tree() {
  local child
  for child in $(pgrep -P "$1" 2>/dev/null); do process_tree "$child"; done
  echo "$1"
}

INTERRUPTED=0
CLAUDE_PID=""
interrupt_run() {
  INTERRUPTED=1
  [ -z "$CLAUDE_PID" ] || stop_run
}

echo "→ /fixall ($MODEL, watchdog ${MAX_MINUTES}m${MAX_USD:+, cap \$$MAX_USD})"
trap interrupt_run INT TERM
"$CLAUDE" -p "/fixall" \
  --model "$MODEL" \
  --permission-mode "${FIXALL_PERMISSION_MODE:-acceptEdits}" \
  "${BUDGET_ARGS[@]}" > "$RUN_OUT" 2>&1 &
CLAUDE_PID=$!
if ! printf '%s\n' "$CLAUDE_PID" > "$ACTIVE_RUN/child.pid" \
   || ! ps -p "$CLAUDE_PID" -o lstart= > "$ACTIVE_RUN/child.started"; then
  # A very short run may have already exited before ps; that is not a write failure.
  if kill -0 "$CLAUDE_PID" 2>/dev/null; then
    interrupt_run
  fi
fi

# A run may last MAX_MINUTES and this loop's runs include xcodebuild simulator
# suites, so it is the most sleep-exposed unattended run on this Mac: idle sleep
# inside that window kills it mid-task (AITD-488, after the web board's
# AWTD-1207, where whole hours of ticks went missing to sleep).
#
# `-w "$CLAUDE_PID"`, NOT `caffeinate "$CLAUDE"`. As a wrapper, caffeinate would
# be the child this script waits on, and the watchdog's kill would land on
# caffeinate while the real run carried on — the wedged run the watchdog exists
# to stop, since launchd starts no second copy of a live label. Asserting
# against the run's pid keeps one process to kill, and the assertion ends with
# the run on its own. No -d: the display may sleep, nobody is watching.
# FIXALL_CAFFEINATE is the test seam, like FIXALL_TSX: a login shell runs
# path_helper, which reorders PATH and puts /usr/bin ahead of anything the
# caller prepended, so a stub cannot be reached by PATH alone. Empty = skip.
CAFFEINATE_BIN="${FIXALL_CAFFEINATE-caffeinate}"
CAFFEINATE_PID=""
if [ -n "$CAFFEINATE_BIN" ] && command -v "$CAFFEINATE_BIN" >/dev/null 2>&1; then
  "$CAFFEINATE_BIN" -i -m -w "$CLAUDE_PID" &
  CAFFEINATE_PID=$!
elif [ -n "$CAFFEINATE_BIN" ]; then
  echo "  ⚠️  no caffeinate at $CAFFEINATE_BIN — idle sleep may kill this run"
fi

watch_run() {
  sleep $((MAX_MINUTES * 60)) &
  local sleeper=$!
  trap 'kill "$sleeper" 2>/dev/null; exit 0' TERM INT
  wait "$sleeper"
  touch "$ACTIVE_RUN/watchdog-fired"
  stop_run
}
watch_run &
WATCHDOG_PID=$!

wait "$CLAUDE_PID"
STATUS=$?
[ "$INTERRUPTED" -eq 0 ] || { wait "$CLAUDE_PID" 2>/dev/null; STATUS=143; }
trap 'exit 143' INT TERM
if [ -n "$CAFFEINATE_PID" ]; then
  kill "$CAFFEINATE_PID" 2>/dev/null || true
fi
if [ ! -f "$ACTIVE_RUN/watchdog-fired" ]; then
  kill "$WATCHDOG_PID" 2>/dev/null
fi
wait "$WATCHDOG_PID" 2>/dev/null
if [ -f "$ACTIVE_RUN/watchdog-fired" ] && [ "$STATUS" -lt 128 ]; then
  STATUS=143
fi
cat "$RUN_OUT" 2>/dev/null
RUN_VERDICT=$(grep -E '^RESULT: ' "$RUN_OUT" 2>/dev/null | tail -1)

# The other half of AITD-426. `claude -p` exiting 0 is not enough: the 17:30 run
# exited 0 with four files still uncommitted, so this recorded OK, the wake keys
# were marked seen rather than struck, and the stall was left to be INFERRED from
# the next tick's skip 30 minutes later. A run that hands back a dirty tree has
# not finished, and saying so here makes it visible at the moment it happens.
#
# Only when the guards confirmed the tree was clean going in — under FIXALL_FORCE
# it may have been dirty all along, and blaming the run for that would be a lie.
#
# And the tree is then PUT BACK, whatever the exit. Reporting the mess was half a
# fix: the next tick still skipped on it until a human came. astrid-web's loop
# wedged that way twice on 2026-09-27 (AWTD-1024, AWTD-1025 — the second killed by
# the watchdog mid-task). So uncommitted work is saved as a WIP commit on the task
# branch — or a wip/ branch, never main — marked UNFINISHED so nobody ships it;
# any branch the run is left on is pushed so the work is reviewable; and HEAD goes
# back to main so the next tick can run. --no-verify because the work is by
# definition unverified. Same guard as above: under FIXALL_FORCE the tree may have
# held someone's work before the run, and that is not the loop's to commit.
LEFT_DIRTY=""
SAVED_BRANCH=""
RESTORE_FAILED=0
if [ "$GUARDS_CONFIRMED_CLEAN" -eq 1 ]; then
  if ! restore_checkout; then
    RESTORE_FAILED=1
    [ "$STATUS" -ne 0 ] || STATUS=92
  fi
  [ -z "$LEFT_DIRTY" ] || [ "$STATUS" -ne 0 ] || STATUS=90
fi

# A run that SAYS it failed has failed, whatever it exits (AITD-440). On
# 2026-09-27 08:30 the astrid MCP server timed out at session start; the session
# wrote "RESULT: FAILED — … never read the queue" and `claude -p` exited 0 anyway,
# so this loop printed RESULT: OK under it, marked the wake keys seen instead of
# striking them, and told the board nothing. Only the LAST RESULT: line counts —
# fixall.md makes it the run's closing verdict. After the dirty-tree check, so
# a run that did both is reported as the stall it causes.
REPORTED_FAILED=""
if [ "$STATUS" -eq 0 ] && [[ "$RUN_VERDICT" == "RESULT: FAILED"* ]]; then
  REPORTED_FAILED="${RUN_VERDICT#RESULT: FAILED}"
  REPORTED_FAILED="${REPORTED_FAILED# — }"
  [ -n "$REPORTED_FAILED" ] || REPORTED_FAILED="no reason given"
  STATUS=91
fi

# Record completion before any bookkeeping: after a reboot the same outcome and
# exact keys must be used. If recovery fails, do not acknowledge anything yet.
OUTCOME=failed
[ "$STATUS" -ne 0 ] || OUTCOME=finished
if ! printf '%s\n' "$OUTCOME" > "$ACTIVE_RUN/outcome" \
   || [ "$RESTORE_FAILED" -ne 0 ] || ! finalize_run; then
  post_to_list "**Scheduled /fixall bookkeeping failed** — its claims, output and wake keys remain in \`$ACTIVE_RUN\`. The next tick retries recovery before starting any new agent; no successful wake acknowledgement was recorded."
  echo "RESULT: FAILED — post-run recovery incomplete; durable state retained"
  exit 1
fi

if [ "$STATUS" -eq 0 ]; then
  echo "RESULT: OK — run finished (see the tasks for what changed)"
  exit 0
fi

# A run that died cannot write its own completion comment, and this is precisely
# the outcome worth hearing about, so the wrapper says it on the board itself.
if [ -n "$LEFT_DIRTY" ] && [ "$STATUS" -eq 90 ]; then
  REASON="run left the tree dirty"
  post_to_list "## Scheduled /fixall left work uncommitted

The run exited cleanly but handed back a dirty tree, which is not a finished run (AITD-426). ${SAVED_BRANCH:+The work is saved as an unverified WIP commit on \`$SAVED_BRANCH\` and the loop is back on main — pick the task up from that branch.}

Uncommitted at the end of the run:

\`\`\`
$(echo "$LEFT_DIRTY" | head -20)
\`\`\`

Log: \`~/Library/Logs/astrid-fixall.log\`"
  echo "RESULT: FAILED — $REASON"
  exit 1
fi

if [ -n "$REPORTED_FAILED" ]; then
  post_to_list "**Scheduled /fixall did not finish** — the run reported FAILED although it exited 0:

> $REPORTED_FAILED

Its wake items got a strike rather than being marked seen, so the next tick tries again. Log: \`~/Library/Logs/astrid-fixall.log\`"
  echo "RESULT: FAILED — run reported: $REPORTED_FAILED"
  exit 1
fi

if [ "$INTERRUPTED" -ne 0 ]; then
  REASON="launcher interrupted (signal $((STATUS - 128)))"
elif [ "$STATUS" -ge 128 ]; then
  REASON="killed after ${MAX_MINUTES}m watchdog timeout (signal $((STATUS - 128)))"
else
  REASON="claude exited $STATUS"
fi
if [ -n "$SAVED_BRANCH" ]; then
  SAVED_NOTE="Its unfinished work is saved on \`$SAVED_BRANCH\` (WIP, unverified)."
else
  SAVED_NOTE="Nothing was pushed by this run."
fi
post_to_list "**Scheduled /fixall did not finish** — $REASON. $SAVED_NOTE Log: ~/Library/Logs/astrid-fixall.log"
echo "RESULT: FAILED — $REASON"
exit 1
