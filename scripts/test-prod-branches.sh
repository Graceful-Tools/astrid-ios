#!/bin/bash
#
# test-prod-branches.sh — the regression test for scripts/sync-prod-branches.sh and
# scripts/advance-app-prod-branch.sh (AITD-434 iOS, AITD-435 Mac).
#
# Runs both scripts for real against a throwaway bare "origin" and clone, with a fake
# `asc-appstore.mjs live` answering from a file. Nothing touches the network or this repo's refs.
#
# What is pinned:
#   - the first release creates <p>-prod and tags <p>-v<version>, for iOS and Mac independently;
#   - a re-run with nothing new released pushes nothing;
#   - a newer release fast-forwards the branch; an older one still moves it, with a warning;
#   - a version tag that already names another commit is never moved (the hand-made mac-v1.0.x);
#   - a locally uploaded build (no Xcode Cloud sha) resolves through <p>-build-<n>, and one with
#     neither is a warning and a non-zero exit, never a guess;
#   - nothing live is a no-op, and a PAUSED phased release warns but still points the branch.
set -u
SRC="$(cd "$(dirname "$0")/.." && pwd)"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

git init -q --bare "$TMP/origin.git"
git clone -q "$TMP/origin.git" "$TMP/repo" 2>/dev/null
cd "$TMP/repo"
git config user.email t@t; git config user.name t
mkdir scripts
cp "$SRC/scripts/sync-prod-branches.sh" "$SRC/scripts/advance-app-prod-branch.sh" scripts/
commit() { echo "$1" > f; git add f; git commit -qm "$1"; git rev-parse HEAD; }
A=$(commit a); B=$(commit b); C=$(commit c)
git push -q origin HEAD:main

# The fake ASC: LIVE_<platform> holds the line `live` would print.
cat > "$TMP/live" <<'STUB'
#!/bin/bash
cat "$LIVE_DIR/$1"
STUB
chmod +x "$TMP/live"
export ASC_LIVE="$TMP/live" LIVE_DIR="$TMP"
live() { printf '%s\n' "$2" > "$TMP/$1"; }

FAILS=0
check() { # <name> <condition...>
  local name="$1"; shift
  if "$@"; then echo "  ok   $name"; else echo "  FAIL $name"; FAILS=$((FAILS + 1)); fi
}
remote_ref() { git ls-remote "$TMP/origin.git" "$1" | cut -f1; }
contains() { [[ "$OUT" == *"$1"* ]]; }

# 1. First release, both platforms.
live ios "1.0	10	$A	-"; live mac "2.0	11	$B	-"
OUT=$(./scripts/sync-prod-branches.sh 2>&1); RC=$?
check "first run exits 0" [ "$RC" -eq 0 ]
check "ios-prod created at the live commit" [ "$(remote_ref refs/heads/ios-prod)" = "$A" ]
check "mac-prod created at its own live commit" [ "$(remote_ref refs/heads/mac-prod)" = "$B" ]
check "ios-v1.0 tagged" [ -n "$(remote_ref refs/tags/ios-v1.0)" ]
check "mac-v2.0 tagged" [ -n "$(remote_ref refs/tags/mac-v2.0)" ]

# 2. Nothing new released.
OUT=$(./scripts/sync-prod-branches.sh ios 2>&1)
check "re-run says it is already there" contains "already at"
check "re-run does not tag again" bash -c "! grep -q tagged <<<\"\$0\"" "$OUT"

# 3. Newer release fast-forwards.
live ios "1.1	12	$C	-"
OUT=$(./scripts/sync-prod-branches.sh ios 2>&1)
check "newer release fast-forwards" contains "fast-forward"
check "ios-prod now at the new commit" [ "$(remote_ref refs/heads/ios-prod)" = "$C" ]

# 4. The store serves an older build: follow it, loudly.
live ios "1.2	13	$B	-"
OUT=$(./scripts/sync-prod-branches.sh ios 2>&1)
check "backwards move warns" contains "NOT a fast-forward"
check "backwards move still moves" [ "$(remote_ref refs/heads/ios-prod)" = "$B" ]

# 5. A hand-made tag naming another commit is left alone.
git tag mac-v2.1 "$A"; git push -q origin mac-v2.1
live mac "2.1	14	$C	-"
OUT=$(./scripts/sync-prod-branches.sh mac 2>&1)
check "existing tag conflict warns" contains "leaving the tag alone"
check "existing tag not moved" [ "$(remote_ref refs/tags/mac-v2.1)" = "$A" ]
check "branch still follows the store" [ "$(remote_ref refs/heads/mac-prod)" = "$C" ]

# 6. A local upload: no run sha, resolved through the build tag.
git tag ios-build-15 "$A"; git push -q origin ios-build-15; git tag -d ios-build-15 >/dev/null
live ios "1.3	15	-	-"
OUT=$(./scripts/sync-prod-branches.sh ios 2>&1); RC=$?
check "local upload resolves via ios-build-<n>" [ "$(remote_ref refs/heads/ios-prod)" = "$A" ]
live ios "1.4	16	-	-"
OUT=$(./scripts/sync-prod-branches.sh ios 2>&1); RC=$?
check "no sha and no build tag warns" contains "cannot tell which commit"
check "...and exits non-zero" [ "$RC" -ne 0 ]
check "...and does not move the branch" [ "$(remote_ref refs/heads/ios-prod)" = "$A" ]

# 7. Nothing live; a paused phased release.
live ios "NONE"
OUT=$(./scripts/sync-prod-branches.sh ios 2>&1); RC=$?
check "nothing live is a quiet no-op" [ "$RC" -eq 0 ]
live ios "1.5	17	$C	PAUSED"
OUT=$(./scripts/sync-prod-branches.sh ios 2>&1)
check "paused rollout warns" contains "PAUSED"
check "paused rollout still points the branch" [ "$(remote_ref refs/heads/ios-prod)" = "$C" ]

echo ""
if [ "$FAILS" -eq 0 ]; then echo "test-prod-branches: all passed"; else echo "test-prod-branches: $FAILS FAILED"; exit 1; fi
