#!/bin/zsh
# fixall-status.sh — "Status?" in one command (npm run fixall:status).
#
# Answering that used to take a session five or six calls every time it was asked: the lock, the
# queue, each Doing task's comments, the Xcode Cloud runs, the builds, an ancestry check
# (2026-11-27, asked three times in one day). Everything here is read-only and reuses the pieces
# the loop already has; nothing is claimed, closed, posted or marked seen.
#
#   Tree      who holds the working tree, the branch, uncommitted files, what is not pushed
#   Queue     what the scheduled run would find (Ready, questions answered, Inbox ideas)
#   Doing     each task waiting on a build, and whether a VALID build carries it yet
#   Builds    the latest Xcode Cloud runs and what they were built from
#   Tooling   whether the astrid-web checkout the helpers run from has fallen behind
#   Loop      the scheduled run's last result lines
#
# A section that cannot be read says so and the rest still prints. Exit 0 always: this reports.
set -u

REPO="${0:A:h:h}"
WEB="${ASTRID_WEB_DIR:-$REPO/../astrid-web}"
TSX="$WEB/node_modules/.bin/tsx"
IOS_LIST_ID="aa41c1a3-bd63-4c6d-9b87-42c6e0aafa36"
LOG="${FIXALL_LOG:-$HOME/Library/Logs/astrid-fixall.log}"
cd "$REPO" || exit 0

section() { print -r -- ""; print -r -- "## $1"; }
indent() { sed 's/^/  /'; }
git_() { git -c core.fsmonitor=false "$@"; }

section "Tree"
if [ -x "$TSX" ]; then
  "$TSX" "$WEB/scripts/fixall-session.ts" status 2>&1 | indent
else
  print -r -- "  lock: cannot tell (no tsx at $TSX)"
fi
print -r -- "  branch: $(git_ rev-parse --abbrev-ref HEAD) at $(git_ log -1 --format='%h %s' | cut -c1-90)"
dirty=$(git_ status --porcelain | wc -l | tr -d ' ')
[ "$dirty" = 0 ] && print -r -- "  clean" || print -r -- "  $dirty uncommitted file(s) — the scheduled run skips a dirty tree"
git_ fetch -q origin 2>/dev/null || print -r -- "  (could not fetch; comparing with what is already here)"
for b in main iosdev macdev; do
  ahead=$(git_ rev-list --count "origin/$b..main" 2>/dev/null) || { print -r -- "  origin/$b: not found"; continue; }
  [ "$ahead" = 0 ] && print -r -- "  origin/$b: has everything on main" \
    || print -r -- "  origin/$b: $ahead commit(s) on main not pushed there"
done

section "Queue"
if [ -x "$TSX" ]; then
  ( cd "$WEB" && "$TSX" scripts/agent-queue-status.ts --agent claude --list "$IOS_LIST_ID" \
      --board ios --include-unassigned --no-write-seen 2>&1 ) | grep -v '^KEYS:' | indent
else
  print -r -- "  cannot tell (no tsx at $TSX)"
fi

section "Doing (waiting on a build)"
node "$REPO/scripts/close-built-tasks.mjs" --dry-run 2>&1 | sed 's/^close-built: //' | indent

section "Builds (Xcode Cloud run = build number)"
node "$REPO/scripts/asc-appstore.mjs" runs --limit 4 2>&1 | cut -c1-110 | indent

section "Tooling (astrid-web checkout the helpers run from)"
if git_ -C "$WEB" rev-parse --git-dir >/dev/null 2>&1; then
  git_ -C "$WEB" fetch -q origin 2>/dev/null
  behind=$(git_ -C "$WEB" rev-list --count HEAD..origin/main 2>/dev/null || echo "?")
  head=$(git_ -C "$WEB" symbolic-ref -q --short HEAD || echo "detached")
  print -r -- "  $head at $(git_ -C "$WEB" log -1 --format='%h (%cs)'), $behind commit(s) behind origin/main"
  [ "$behind" != "?" ] && [ "$behind" -gt 200 ] && \
    print -r -- "  STALE: the claim, queue and MCP helpers are that far behind what is deployed"
else
  print -r -- "  no checkout at $WEB"
fi

section "Loop (last scheduled results)"
if [ -r "$LOG" ]; then
  grep -E '^─+ fixall loop|^RESULT:' "$LOG" | tail -6 | cut -c1-160 | indent
else
  print -r -- "  no log at $LOG"
fi
exit 0
