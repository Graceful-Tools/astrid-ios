#!/bin/zsh
# update-web-tooling.sh — keep the astrid-web checkout the loop's helpers run from on origin/main.
#
# The claim, queue, handback and MCP helpers all run from ../astrid-web. Nothing moved that
# checkout, and on 2026-11-27 it was a detached HEAD twelve days and 1,394 commits behind what
# was deployed (ADEV-354; Jon: "Fast forward"). scripts/fixall-loop.sh runs this every tick.
#
# It fast-forwards and nothing else. It leaves the checkout alone, saying why in one line, when:
#   - a live /fixall session holds this tree or that one (its helpers are in use)
#   - the checkout has uncommitted changes to tracked files
#   - it is on a branch other than main (someone is working there)
#   - it has commits origin/main lacks (a fast-forward is not possible)
# After moving it: `npm ci` when package-lock.json changed, the MCP server is rebuilt, and one
# helper is run as a smoke check. If any of that fails, the checkout goes back to where it was
# and the line says FAILED, so a broken update never leaves the loop without its helpers.
#
# Prints at most a few lines, each starting `web-tooling:`. Exit 0 unless the rollback failed too.
#
# Env: ASTRID_WEB_DIR (default: sibling astrid-web), WEB_TOOLING_NPM (default: npm; the test
# points it at a stub).
set -u

REPO="${0:A:h:h}"
WEB="${ASTRID_WEB_DIR:-$REPO/../astrid-web}"
NPM="${WEB_TOOLING_NPM:-npm}"
TSX="$WEB/node_modules/.bin/tsx"
say() { print -r -- "web-tooling: $*"; }
git_() { git -c core.fsmonitor=false -C "$WEB" "$@"; }

git_ rev-parse --git-dir >/dev/null 2>&1 || { say "no checkout at $WEB"; exit 0; }

# A live session in either tree is using the helpers right now.
if [ -x "$TSX" ]; then
  for tree in "$REPO" "$WEB"; do
    held=$( cd "$tree" 2>/dev/null && "$TSX" "$WEB/scripts/fixall-session.ts" status 2>/dev/null )
    case "$held" in *", live)"*) say "left alone — a live session holds ${tree:t}"; exit 0 ;; esac
  done
fi

# Tracked files only. An untracked file does not stop a fast-forward (git refuses the merge
# itself if one is in the way), and a leftover build bundle the newer .gitignore no longer names
# would otherwise stop every update for good: mcp/astrid-mcp-oauth-http did, the first time.
[ -z "$(git_ status --porcelain --untracked-files=no)" ] || { say "left alone — uncommitted changes in $WEB"; exit 0; }
branch=$(git_ symbolic-ref -q --short HEAD || true)
[ -z "$branch" ] || [ "$branch" = main ] || { say "left alone — on branch $branch"; exit 0; }

git_ fetch -q origin 2>/dev/null || { say "could not fetch; left at $(git_ rev-parse --short HEAD)"; exit 0; }
old=$(git_ rev-parse HEAD)
new=$(git_ rev-parse origin/main 2>/dev/null) || { say "no origin/main"; exit 0; }
[ "$old" != "$new" ] || exit 0   # current: the quiet, usual case
git_ merge-base --is-ancestor "$old" "$new" \
  || { say "left alone — $(git_ rev-parse --short HEAD) has commits origin/main lacks"; exit 0; }

count=$(git_ rev-list --count "$old..$new")
git_ merge -q --ff-only "$new" >/dev/null 2>&1 || { say "FAILED — could not fast-forward; still at ${old[1,8]}"; exit 0; }

prepare() {  # prepare <rev before>: dependencies, the MCP build, one helper as a smoke check
  if ! git_ diff --quiet "$1" HEAD -- package-lock.json; then
    ( cd "$WEB" && "$NPM" ci --no-audit --no-fund ) >/dev/null 2>&1 || { why="npm ci"; return 1; }
  fi
  ( cd "$WEB" && "$NPM" run -s build:mcp:oauth ) >/dev/null 2>&1 || { why="the MCP build"; return 1; }
  ( cd "$WEB" && "$TSX" scripts/fixall-session.ts status ) >/dev/null 2>&1 || { why="the helper smoke check"; return 1; }
}

why=""
if prepare "$old"; then
  say "fast-forwarded $count commit(s), ${old[1,8]} -> ${new[1,8]}"
  exit 0
fi

# Back to where it was. The tree was clean before, so a hard reset loses nothing.
failed="$why"
git_ reset -q --hard "$old"
if prepare "$new"; then
  say "FAILED — $failed did not work at ${new[1,8]}; back at ${old[1,8]}"
  exit 0
fi
say "FAILED — $failed did not work at ${new[1,8]}, and going back to ${old[1,8]} failed at $why. The helpers may be broken."
exit 1
