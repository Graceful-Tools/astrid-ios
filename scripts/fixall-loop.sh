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
#   CLAUDE_BIN          path to the claude CLI (default: ~/.local/bin/claude)
#   FIXALL_FORCE=1      skip the dirty-tree/branch guard (testing only)

set -u
export PATH="/opt/homebrew/bin:$PATH"

REPO="${0:A:h:h}"
WEB="$REPO/../astrid-web"
TSX="$WEB/node_modules/.bin/tsx"
CLAUDE="${CLAUDE_BIN:-$HOME/.local/bin/claude}"
MODEL="${FIXALL_MODEL:-opus}"
MAX_MINUTES="${FIXALL_MAX_MINUTES:-50}"
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

if [ ! -x "$CLAUDE" ]; then
  echo "RESULT: FAILED — no claude CLI at $CLAUDE (set CLAUDE_BIN)"
  exit 1
fi

# ── The run ──────────────────────────────────────────────────────────────────
# Watchdog: launchd will not start a second copy of a label while the first is
# alive, so one wedged run silently swallows every later tick until someone
# notices. macOS ships no `timeout`, hence the subshell.
echo "→ /fixall ($MODEL, watchdog ${MAX_MINUTES}m)"
"$CLAUDE" -p "/fixall" --model "$MODEL" --permission-mode "${FIXALL_PERMISSION_MODE:-acceptEdits}" &
CLAUDE_PID=$!

( sleep $((MAX_MINUTES * 60)); kill -TERM "$CLAUDE_PID" 2>/dev/null ) &
WATCHDOG_PID=$!

wait "$CLAUDE_PID"
STATUS=$?
kill "$WATCHDOG_PID" 2>/dev/null

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
