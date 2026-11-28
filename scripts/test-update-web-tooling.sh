#!/bin/bash
# test-update-web-tooling.sh — pins scripts/update-web-tooling.sh against a throwaway checkout.
#
# The script moves a checkout other sessions share, every tick, unattended (ADEV-354). So what
# matters is as much when it does NOT move it (dirty, on a branch, diverged, in use) as that it
# fast-forwards, and that a failed update puts the checkout back.
set -u
cd "$(dirname "$0")/.."
SCRIPT="$PWD/scripts/update-web-tooling.sh"
TMP=$(mktemp -d "${TMPDIR:-/tmp}/astrid-web-tooling-test.XXXXXXXX") || exit 1
trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
ok() { PASS=$((PASS + 1)); }
bad() { FAIL=$((FAIL + 1)); echo "✗ $1"; [ -n "${2:-}" ] && echo "    $2"; }
check() { if [ "$2" = "$3" ]; then ok; else bad "$1" "expected '$3', got '$2'"; fi; }
has() { case "$2" in *"$3"*) ok ;; *) bad "$1" "wanted '$3' in: $2" ;; esac; }
g() { git -c user.name=t -c user.email=t@t "$@"; }

ORIGIN="$TMP/origin"; WEB="$TMP/astrid-web"; CALLS="$TMP/npm-calls"
g init -q -b main "$ORIGIN"
printf 'node_modules\n' > "$ORIGIN/.gitignore"; echo 1 > "$ORIGIN/package-lock.json"
g -C "$ORIGIN" add -A && g -C "$ORIGIN" commit -q -m first
git clone -q "$ORIGIN" "$WEB" && git -C "$WEB" checkout -q --detach
mkdir -p "$WEB/node_modules/.bin" "$TMP/bin"
# Stubs: tsx answers the lock question from $TMP/held; npm records its calls and fails on demand.
printf '#!/bin/sh\ncat "%s/held" 2>/dev/null\nexit 0\n' "$TMP" > "$WEB/node_modules/.bin/tsx"
printf '#!/bin/sh\necho "$*" >> "%s"\n[ -e "%s/npm-fails" ] && [ ! -e "%s/npm-failed-once" ] && { touch "%s/npm-failed-once"; exit 1; }\nexit 0\n' \
  "$CALLS" "$TMP" "$TMP" "$TMP" > "$TMP/bin/npm"
chmod +x "$WEB/node_modules/.bin/tsx" "$TMP/bin/npm"
export ASTRID_WEB_DIR="$WEB" WEB_TOOLING_NPM="$TMP/bin/npm"
head_() { git -C "$WEB" rev-parse HEAD; }
advance() {  # advance <file>: one new commit on origin's main touching <file>
  date +%s%N >> "$ORIGIN/$1"; g -C "$ORIGIN" add -A; g -C "$ORIGIN" commit -q -m "change $1"
  git -C "$ORIGIN" rev-parse HEAD
}

check "already current: says nothing" "$("$SCRIPT")" ""

new=$(advance README.md); : > "$CALLS"
out=$("$SCRIPT"); has "behind: it fast-forwards and says so" "$out" "fast-forwarded 1 commit(s)"
check "the detached checkout is on origin/main" "$(head_)" "$new"
check "no npm ci when the lockfile did not change; the MCP server is rebuilt" "$(cat "$CALLS")" "run -s build:mcp:oauth"

echo leftover > "$WEB/old-bundle"   # untracked, as a build output dropped from .gitignore is
new=$(advance package-lock.json); : > "$CALLS"
"$SCRIPT" >/dev/null; check "a lockfile change moves it too, past an untracked file" "$(head_)" "$new"
has "a lockfile change runs npm ci" "$(cat "$CALLS")" "ci --no-audit --no-fund"

before=$(head_); advance README.md >/dev/null
echo wip > "$WEB/README.md"
has "uncommitted changes: left alone" "$("$SCRIPT")" "left alone — uncommitted changes"
check "…and not moved" "$(head_)" "$before"
git -C "$WEB" checkout -q -- README.md 2>/dev/null || rm -f "$WEB/README.md"

git -C "$WEB" checkout -q -b fix/something
has "on a branch: left alone" "$("$SCRIPT")" "left alone — on branch fix/something"
git -C "$WEB" checkout -q --detach && git -C "$WEB" branch -q -D fix/something

echo "claude-code (pid 1, live) has held /somewhere since now" > "$TMP/held"
has "a live session: left alone" "$("$SCRIPT")" "left alone — a live session holds"
check "…and not moved" "$(head_)" "$before"
rm "$TMP/held"

g -C "$WEB" commit -q --allow-empty -m local-only; local_head=$(head_)
has "commits origin lacks: left alone" "$("$SCRIPT")" "has commits origin/main lacks"
check "…and not moved" "$(head_)" "$local_head"
git -C "$WEB" checkout -q --detach "$before"

touch "$TMP/npm-fails"
out=$("$SCRIPT"); has "a failed build says FAILED" "$out" "FAILED — the MCP build did not work"
has "…and says it went back" "$out" "back at"
check "…and the checkout is back where it was" "$(head_)" "$before"
check "…with nothing left dirty" "$(git -C "$WEB" status --porcelain --untracked-files=no)" ""
rm "$TMP/npm-fails" "$TMP/npm-failed-once"

"$SCRIPT" >/dev/null; check "the next tick takes the update" "$(head_)" "$(git -C "$ORIGIN" rev-parse HEAD)"

echo ""
if [ "$FAIL" = 0 ]; then echo "✓ update-web-tooling: $PASS checks passed"; exit 0; fi
echo "✗ update-web-tooling: $FAIL failed, $PASS passed"; exit 1
