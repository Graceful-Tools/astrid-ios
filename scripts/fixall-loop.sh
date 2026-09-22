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
if [ "${FIXALL_FORCE:-0}" != "1" ]; then
  BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
  if [ -n "$(git status --porcelain 2>/dev/null)" ]; then
    echo "RESULT: SKIPPED — working tree is dirty, leaving it alone"
    exit 0
  fi
  if [ "$BRANCH" != "main" ]; then
    echo "RESULT: SKIPPED — HEAD is on $BRANCH, not main"
    exit 0
  fi
fi

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
QUEUE_OUT=$( cd "$WEB" && "$TSX" scripts/agent-queue-status.ts --agent claude --list "$IOS_LIST_ID" --no-write-seen 2>&1 )
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

echo "→ /fixall ($MODEL, watchdog ${MAX_MINUTES}m${MAX_USD:+, cap \$$MAX_USD})"
"$CLAUDE" -p "/fixall" \
  --model "$MODEL" \
  --permission-mode "${FIXALL_PERMISSION_MODE:-acceptEdits}" \
  "${BUDGET_ARGS[@]}" &
CLAUDE_PID=$!

( sleep $((MAX_MINUTES * 60)); kill -TERM "$CLAUDE_PID" 2>/dev/null ) &
WATCHDOG_PID=$!

wait "$CLAUDE_PID"
STATUS=$?
kill "$WATCHDOG_PID" 2>/dev/null

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
if [ "$STATUS" -ge 128 ]; then
  REASON="killed after ${MAX_MINUTES}m watchdog timeout (signal $((STATUS - 128)))"
else
  REASON="claude exited $STATUS"
fi
post_to_list "**Scheduled /fixall did not finish** — $REASON. Nothing was pushed by this run. Log: ~/Library/Logs/astrid-fixall.log"
echo "RESULT: FAILED — $REASON"
exit 1
