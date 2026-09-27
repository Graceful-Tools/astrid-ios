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
#   FIXALL_MAX_MINUTES  watchdog, kills a wedged run (default: 50)
#   FIXALL_MAX_USD      hard spend cap for one run (default: 10; empty = no cap)
#   CLAUDE_BIN          path to the claude CLI (default: ~/.local/bin/claude)
#   FIXALL_FORCE=1      skip the dirty-tree/branch guard (testing only)
#   FIXALL_TSX          path to tsx (default: astrid-web's). scripts/test-fixall-loop.sh
#                       points it at a stub so the test can run this loop for real without
#                       taking the working-tree lock or calling the board.
#   FIXALL_STALL_STATE  where the consecutive-skip count lives (default: beside the log)
#   FIXALL_STALL_ALERT_AFTER  how many skips in a row before saying so (default: 3)
#   FIXALL_PROD_SYNC    the ios-prod/mac-prod sync run each tick (default:
#                       scripts/sync-prod-branches.sh; empty = skip, as the test does)

set -u
export PATH="/opt/homebrew/bin:$PATH"

REPO="${0:A:h:h}"
WEB="$REPO/../astrid-web"
TSX="${FIXALL_TSX:-$WEB/node_modules/.bin/tsx}"
CLAUDE="${CLAUDE_BIN:-$HOME/.local/bin/claude}"
MODEL="${FIXALL_MODEL:-opus}"
MAX_MINUTES="${FIXALL_MAX_MINUTES:-50}"
MAX_USD="${FIXALL_MAX_USD-10}"
IOS_LIST_ID="aa41c1a3-bd63-4c6d-9b87-42c6e0aafa36"
STALL_STATE="${FIXALL_STALL_STATE:-$HOME/Library/Logs/astrid-fixall-stall.state}"
STALL_ALERT_AFTER="${FIXALL_STALL_ALERT_AFTER:-3}"
PROD_SYNC="${FIXALL_PROD_SYNC-$REPO/scripts/sync-prod-branches.sh}"

echo "──────── fixall loop $(date '+%Y-%m-%d %H:%M:%S') ────────"

cd "$REPO" || { echo "RESULT: FAILED — cannot enter $REPO"; exit 1; }

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

It has skipped **$count ticks in a row**, first at \`$since\`. That guard is doing its job — it will not clobber work in progress — but it will keep refusing until the tree is put back, so this says so once rather than waiting to be asked.

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

"$TSX" "$WEB/scripts/fixall-session.ts" acquire --pid $$ --harness claude-code
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
trap release_lock EXIT INT TERM

# The lock is held by THIS script, whose pid the agent cannot see. Inside
# `claude -p`, $PPID is the claude process — a different LIVE pid — so the
# agent's own `acquire` would return 2 and it would stop before reading the
# queue. fixall.md checks this variable and skips the acquire when it is set.
export ASTRID_FIXALL_LOCK_HELD=1

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
QUEUE_OUT=$( cd "$WEB" && "$TSX" scripts/agent-queue-status.ts --agent claude --list "$IOS_LIST_ID" --include-unassigned --no-write-seen 2>&1 )
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
# until the clock runs out — which the watchdog would not stop for 50 minutes.
# --max-budget-usd only works with -p, which is the mode this always runs in.
BUDGET_ARGS=()
[ -n "$MAX_USD" ] && BUDGET_ARGS=(--max-budget-usd "$MAX_USD")

# The run's output goes to a file as well as the log, because the loop has to read
# it back: see RUN_VERDICT below. A plain redirect, not a pipe to tee, so $! is
# still claude itself and the watchdog kills the right process. `claude -p` prints
# only its final message, so nothing is lost by echoing it once the run ends.
RUN_OUT=$(mktemp -t fixall-run) || RUN_OUT=/dev/null
echo "→ /fixall ($MODEL, watchdog ${MAX_MINUTES}m${MAX_USD:+, cap \$$MAX_USD})"
"$CLAUDE" -p "/fixall" \
  --model "$MODEL" \
  --permission-mode "${FIXALL_PERMISSION_MODE:-acceptEdits}" \
  "${BUDGET_ARGS[@]}" > "$RUN_OUT" 2>&1 &
CLAUDE_PID=$!

( sleep $((MAX_MINUTES * 60)); kill -TERM "$CLAUDE_PID" 2>/dev/null ) &
WATCHDOG_PID=$!

wait "$CLAUDE_PID"
STATUS=$?
kill "$WATCHDOG_PID" 2>/dev/null
cat "$RUN_OUT" 2>/dev/null
RUN_VERDICT=$(grep -E '^RESULT: ' "$RUN_OUT" 2>/dev/null | tail -1)
[ "$RUN_OUT" != /dev/null ] && rm -f "$RUN_OUT"

# The other half of AITD-426. `claude -p` exiting 0 is not enough: the 17:30 run
# exited 0 with four files still uncommitted, so this recorded OK, the wake keys
# were marked seen rather than struck, and the stall was left to be INFERRED from
# the next tick's skip 30 minutes later. A run that hands back a dirty tree has
# not finished, and saying so here makes it visible at the moment it happens.
#
# Only when the guards confirmed the tree was clean going in — under FIXALL_FORCE
# it may have been dirty all along, and blaming the run for that would be a lie.
LEFT_DIRTY=""
if [ "$STATUS" -eq 0 ] && [ "$GUARDS_CONFIRMED_CLEAN" -eq 1 ]; then
  LEFT_DIRTY=$(git status --porcelain 2>/dev/null)
  [ -n "$LEFT_DIRTY" ] && STATUS=90
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

# Phase two of waking, before the RESULT lines so that line stays last (the
# header promises it). A finished run had its chance at the preflight's items:
# they are marked seen and will not wake another run. A run that died gives them
# a strike instead. Same `cd "$WEB"` as the preflight — loadScriptEnv() reads
# .env.local from the cwd, and that file lives in astrid-web.
if [ -n "${QUEUE_KEYS:-}" ]; then
  if [ "$STATUS" -eq 0 ]; then
    ( cd "$WEB" && "$TSX" scripts/agent-queue-status.ts --agent claude --list "$IOS_LIST_ID" --mark-seen --seen-keys "$QUEUE_KEYS" 2>&1 ) | sed 's/^/  /'
  else
    ( cd "$WEB" && "$TSX" scripts/agent-queue-status.ts --agent claude --list "$IOS_LIST_ID" --mark-seen --failed --seen-keys "$QUEUE_KEYS" 2>&1 ) | sed 's/^/  /'
  fi
fi

if [ "$STATUS" -eq 0 ]; then
  echo "RESULT: OK — run finished (see the tasks for what changed)"
  exit 0
fi

# A run that died cannot write its own completion comment, and this is precisely
# the outcome worth hearing about, so the wrapper says it on the board itself.
if [ -n "$LEFT_DIRTY" ]; then
  REASON="run left the tree dirty"
  post_to_list "## Scheduled /fixall left work uncommitted

The run exited cleanly but handed back a dirty tree, which is not a finished run — every tick from here will skip on it until someone puts it back (AITD-426).

On branch \`$(git rev-parse --abbrev-ref HEAD 2>/dev/null)\`:

\`\`\`
$(echo "$LEFT_DIRTY" | head -20)
\`\`\`

Nothing was pushed. Log: \`~/Library/Logs/astrid-fixall.log\`"
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

if [ "$STATUS" -ge 128 ]; then
  REASON="killed after ${MAX_MINUTES}m watchdog timeout (signal $((STATUS - 128)))"
else
  REASON="claude exited $STATUS"
fi
post_to_list "**Scheduled /fixall did not finish** — $REASON. Nothing was pushed by this run. Log: ~/Library/Logs/astrid-fixall.log"
echo "RESULT: FAILED — $REASON"
exit 1
