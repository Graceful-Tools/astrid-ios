#!/bin/bash
# test-core-worktree.sh — pins scripts/core/worktree.sh against a throwaway repository.
#
# The script is the scheduled run's one allowlisted way into an astrid-core worktree, so two
# things must hold: the worktree lands under the folder the loop adds before the run (anywhere
# else is an approval request per edit, which is how ADEV-328 sat 13 hours), and `run` passes
# only cargo, git and gh, so the allowlist entry for this script is not a way around the rest.
set -u
cd "$(dirname "$0")/.."
SCRIPT="$PWD/scripts/core/worktree.sh"
TMP=$(mktemp -d "${TMPDIR:-/tmp}/astrid-core-worktree-test.XXXXXXXX") || exit 1
trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
ok() { PASS=$((PASS + 1)); }
bad() { FAIL=$((FAIL + 1)); echo "✗ $1"; [ -n "${2:-}" ] && echo "    $2"; }
check() { if [ "$2" = "$3" ]; then ok; else bad "$1" "expected '$3', got '$2'"; fi; }

# An "origin" and the shared checkout cloned from it.
git init -q -b main "$TMP/origin" && git -C "$TMP/origin" -c user.name=t -c user.email=t@t commit -q --allow-empty -m first
git clone -q "$TMP/origin" "$TMP/astrid-core"
export ASTRID_CORE_DIR="$TMP/astrid-core"
unset ASTRID_CORE_WORKTREES

out=$("$SCRIPT" start adev-1 2>&1); check "start succeeds" "$?" 0
case "$out" in "RESULT: OK — $TMP/astrid-core-worktrees/adev-1 on fix/adev-1"*) ok ;; *) bad "start says where and on which branch" "$out" ;; esac
check "the worktree is under the one added folder" "$("$SCRIPT" path adev-1)" "$TMP/astrid-core-worktrees/adev-1"
check "the shared checkout stays on its own branch" "$(git -C "$TMP/astrid-core" rev-parse --abbrev-ref HEAD)" main

check "run goes inside the worktree" "$("$SCRIPT" run adev-1 git rev-parse --abbrev-ref HEAD)" "fix/adev-1"
for word in rm sh bash env npx; do
  "$SCRIPT" run adev-1 "$word" -c true >/dev/null 2>&1; check "run refuses $word" "$?" 1
done
"$SCRIPT" start adev-1 >/dev/null 2>&1; check "start refuses a slug in use" "$?" 1
for slug in "Bad Slug" "../escape" "a/b" "-x"; do
  "$SCRIPT" start "$slug" >/dev/null 2>&1; check "start refuses the slug '$slug'" "$?" 1
done
"$SCRIPT" run nope git status >/dev/null 2>&1; check "run needs a started worktree" "$?" 1

touch "$TMP/astrid-core-worktrees/adev-1/left.txt"
"$SCRIPT" finish adev-1 >/dev/null 2>&1; check "finish refuses uncommitted work" "$?" 1
rm "$TMP/astrid-core-worktrees/adev-1/left.txt"
"$SCRIPT" finish adev-1 >/dev/null 2>&1; check "finish succeeds when clean" "$?" 0
[ ! -e "$TMP/astrid-core-worktrees/adev-1" ] && ok || bad "finish removes the worktree"
check "finish removes the branch" "$(git -C "$TMP/astrid-core" branch --list fix/adev-1)" ""

echo ""
if [ "$FAIL" = 0 ]; then echo "✓ core-worktree: $PASS checks passed"; exit 0; fi
echo "✗ core-worktree: $FAIL failed, $PASS passed"; exit 1
