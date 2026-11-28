#!/bin/bash
# Work astrid-core from here in a worktree a scheduled /fixall run can actually reach.
#
#   scripts/core/worktree.sh start  <slug>             # fresh origin/main -> branch fix/<slug>
#   scripts/core/worktree.sh path   <slug>             # where it is (edit files there)
#   scripts/core/worktree.sh run    <slug> cargo …     # cargo, git or gh, run inside it
#   scripts/core/worktree.sh gate   <slug>             # astrid-core's whole local gate
#   scripts/core/worktree.sh finish <slug>             # remove the worktree and its local branch
#
# Why a script. The scheduled run's allowlist matches a command by its first words, and the run
# may only `cd` and edit inside the folders it was started with. A worktree made mid-run at
# ../astrid-core-<slug> is neither: every `cd … && cargo test` and every edit there was a
# 20-minute approval request (ADEV-328 sat 13 hours on the first one). So the worktrees live under
# ONE folder, ../astrid-core-worktrees, which scripts/fixall-loop.sh adds to the run before it
# starts, and every command in them goes through this one allowlisted entry point.
#
# `run` takes cargo, git and gh only, the same three the allowlist already grants here; it is a
# way to reach the worktree, not a way around the allowlist.
#
# Env: ASTRID_CORE_DIR (default ../astrid-core), ASTRID_CORE_WORKTREES (default <core>-worktrees),
# ASTRID_WEB_DIR (default ../astrid-web; the gate reads its origin/main fixtures).
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CORE="${ASTRID_CORE_DIR:-$(dirname "$ROOT")/astrid-core}"
TREES="${ASTRID_CORE_WORKTREES:-${CORE%/}-worktrees}"
WEB="${ASTRID_WEB_DIR:-$(dirname "$ROOT")/astrid-web}"

usage() { sed -n '3,8p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 2; }
fail() { echo "RESULT: FAILED — $*" >&2; exit 1; }

ACTION="${1:-}"; SLUG="${2:-}"
[ -n "$ACTION" ] && [ -n "$SLUG" ] || usage
[[ "$SLUG" =~ ^[a-z0-9][a-z0-9-]*$ ]] || fail "a slug is lowercase letters, digits and dashes (got '$SLUG')"
shift 2
TREE="$TREES/$SLUG"
BRANCH="fix/$SLUG"

[ -d "$CORE/.git" ] || [ -f "$CORE/.git" ] || fail "no astrid-core checkout at $CORE (set ASTRID_CORE_DIR)"
need_tree() { [ -d "$TREE" ] || fail "no worktree for '$SLUG' — run: scripts/core/worktree.sh start $SLUG"; }

case "$ACTION" in
  start)
    [ -e "$TREE" ] && fail "$TREE already exists — finish it first, or pick another slug"
    mkdir -p "$TREES" || fail "could not create $TREES"
    # Never check out or edit the shared checkout: other loops read it. Fetch and branch off origin.
    git -C "$CORE" fetch -q origin || fail "could not fetch astrid-core's origin"
    git -C "$CORE" worktree add -q "$TREE" -b "$BRANCH" origin/main || fail "could not add the worktree"
    echo "RESULT: OK — $TREE on $BRANCH at $(git -C "$TREE" log -1 --format='%h %s')"
    ;;
  path)
    need_tree
    echo "$TREE"
    ;;
  run)
    need_tree
    case "${1:-}" in
      cargo|git|gh) ;;
      *) fail "run takes cargo, git or gh (got '${1:-nothing}')" ;;
    esac
    cd "$TREE" && exec "$@"
    ;;
  gate)
    need_tree
    cd "$TREE" || fail "could not enter $TREE"
    # astrid-core CLAUDE.md §Quality gate, in its order. Stops at the first red step and names it.
    step() {
      echo "→ $*"
      "$@" || fail "core gate: \`$*\` (in $TREE)"
    }
    step cargo fmt --all -- --check
    step cargo clippy --all-targets --all-features -- -D warnings
    step cargo test --workspace
    step cargo test -p astrid-rules --no-default-features
    step cargo clippy -p astrid-rules --no-default-features --all-targets -- -D warnings
    # Against astrid-web's origin/main, as CI checks it, not whatever the local web checkout
    # has checked out: that one sat 1,374 commits behind on 2026-11-27 and failed this step for
    # a change that had nothing to do with contracts.
    FIXTURES="$(mktemp -d)"; trap 'rm -rf "$FIXTURES"' EXIT
    git -C "$WEB" fetch -q origin 2>/dev/null || echo "  (could not fetch astrid-web; using the origin/main already here)"
    git -C "$WEB" archive origin/main contracts/fixtures | tar -x -C "$FIXTURES" \
      || fail "core gate: could not read astrid-web origin/main's contracts/fixtures from $WEB"
    step cargo xtask check-contracts "$FIXTURES"
    step cargo xtask check-design
    step cargo xtask check-strings
    step cargo xtask check-schema
    step cargo xtask check-deny
    step cargo build -p astrid-rules --target wasm32-unknown-unknown
    echo "RESULT: OK — core gate green in $TREE"
    ;;
  finish)
    need_tree
    git -C "$CORE" worktree remove "$TREE" || fail "worktree has uncommitted changes — commit or discard them, then finish"
    git -C "$CORE" branch -q -D "$BRANCH" 2>/dev/null || true
    echo "RESULT: OK — removed $TREE and $BRANCH"
    ;;
  *) usage ;;
esac
