#!/bin/bash
#
# advance-app-prod-branch.sh <ios|mac> <version> <sha>
#
# Points `ios-prod` / `mac-prod` at the commit the App Store is serving for that platform, and
# tags it `ios-v<version>` / `mac-v<version>` (AITD-434 / AITD-435; epic AWTD-1012). The web's
# `prod` is the same idea — astrid-web scripts/advance-prod-branch.sh.
#
# "Prod" means RELEASED ON THE APP STORE (READY_FOR_SALE), not uploaded to TestFlight (Jon,
# 2026-09-26). With the branch, "what are users running" is a ref:
#
#   git log origin/ios-prod..origin/main     what the next App Store release would add
#   git diff mac-v1.1.1 mac-v1.1.2           what one release changed
#
# ONLY AUTOMATION MOVES IT. scripts/sync-prod-branches.sh calls this after App Store Connect
# says which version is live and which commit its build came from. Nobody commits to it.
#
# It follows the store, including backwards: a branch that disagrees with the store is worse
# than none, so a non-fast-forward still moves and says so with a warning. A version TAG never
# moves — one that already names another commit is left alone, with a warning, because a
# release tag that changes under you is a lie about history (the hand-made mac-v1.0.x tags were
# the reason to automate this; they must keep meaning what they meant).
#
# PROD_REMOTE (default origin) exists for scripts/test-prod-branches.sh.

set -euo pipefail

PLATFORM="${1:?usage: advance-app-prod-branch.sh <ios|mac> <version> <sha>}"
VERSION="${2:?usage: advance-app-prod-branch.sh <ios|mac> <version> <sha>}"
SHA_IN="${3:?usage: advance-app-prod-branch.sh <ios|mac> <version> <sha>}"
REMOTE="${PROD_REMOTE:-origin}"

case "$PLATFORM" in ios|mac) ;; *) echo "platform must be ios or mac, not \"$PLATFORM\"" >&2; exit 2 ;; esac

BRANCH="$PLATFORM-prod"
TAG="$PLATFORM-v$VERSION"

git fetch -q "$REMOTE" "$SHA_IN" 2>/dev/null || true
SHA=$(git rev-parse -q --verify "$SHA_IN^{commit}") \
  || { echo "::warning::$BRANCH: commit ${SHA_IN:0:7} for $PLATFORM $VERSION is not in this repository — not moving"; exit 1; }

git fetch -q "$REMOTE" "+refs/heads/$BRANCH:refs/remotes/$REMOTE/$BRANCH" 2>/dev/null || true
git fetch -q "$REMOTE" "+refs/tags/$TAG:refs/tags/$TAG" 2>/dev/null || true

PUSH=()
if OLD=$(git rev-parse -q --verify "refs/remotes/$REMOTE/$BRANCH"); then
  if [ "$OLD" = "$SHA" ]; then
    echo "$BRANCH is already at ${SHA:0:7} ($PLATFORM $VERSION)"
  elif git merge-base --is-ancestor "$OLD" "$SHA"; then
    echo "$BRANCH: ${OLD:0:7} → ${SHA:0:7} ($PLATFORM $VERSION, fast-forward, $(git rev-list --count "$OLD..$SHA") commits)"
    PUSH+=("+$SHA:refs/heads/$BRANCH")
  else
    echo "::warning::$BRANCH moved ${OLD:0:7} → ${SHA:0:7} ($PLATFORM $VERSION), which is NOT a fast-forward — the store is serving an older or unrelated build"
    PUSH+=("+$SHA:refs/heads/$BRANCH")
  fi
else
  echo "$BRANCH does not exist yet — creating it at ${SHA:0:7} ($PLATFORM $VERSION)"
  PUSH+=("+$SHA:refs/heads/$BRANCH")
fi

if TAGGED=$(git rev-parse -q --verify "refs/tags/$TAG^{commit}"); then
  if [ "$TAGGED" != "$SHA" ]; then
    echo "::warning::$TAG already names ${TAGGED:0:7}, not ${SHA:0:7} — leaving the tag alone"
  fi
else
  git tag "$TAG" "$SHA"
  PUSH+=("refs/tags/$TAG")
  echo "tagged $TAG"
fi

[ ${#PUSH[@]} -eq 0 ] || git push -q "$REMOTE" "${PUSH[@]}"
