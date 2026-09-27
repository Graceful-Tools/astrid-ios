#!/bin/bash
#
# sync-prod-branches.sh [ios] [mac]   (default: both)
#
# Asks App Store Connect what is LIVE for each platform and moves `ios-prod` / `mac-prod` to
# the commit it was built from (AITD-434 / AITD-435). Polling rather than a hook, because
# nothing on this machine sees the moment a release goes live: Apple's review and the "release"
# button both happen days after the upload. scripts/fixall-loop.sh runs this every tick; a tick
# where nothing was released changes nothing and pushes nothing.
#
# Which commit: a build number IS its Xcode Cloud run number, and the run knows its sha
# (`asc-appstore.mjs live`). A build uploaded from this machine has no run, so it falls back to
# the `<platform>-build-<n>` tag scripts/appstore-release.sh pushes when an upload is accepted.
#
# A PAUSED phased release is still live for the users who got it, so the branch still points at
# it — with a warning, since a halted rollout usually means someone is deciding whether to pull it.
#
# Exit 0 unless a platform could not be resolved. ASC_LIVE (default `node scripts/asc-appstore.mjs
# live`) and PROD_REMOTE exist for scripts/test-prod-branches.sh.

set -uo pipefail
cd "$(dirname "$0")/.."

LIVE_CMD="${ASC_LIVE:-node scripts/asc-appstore.mjs live}"
REMOTE="${PROD_REMOTE:-origin}"
PLATFORMS=("$@"); [ ${#PLATFORMS[@]} -gt 0 ] || PLATFORMS=(ios mac)

status=0
for p in "${PLATFORMS[@]}"; do
  if ! out=$($LIVE_CMD "$p" 2>&1); then
    echo "::warning::$p-prod: could not ask App Store Connect what is live — $(echo "$out" | tail -1)"
    status=1; continue
  fi
  if [ "$out" = "NONE" ]; then
    echo "$p-prod: no version is READY_FOR_SALE — nothing to point at"
    continue
  fi
  IFS=$'\t' read -r version build sha phased <<<"$out"

  if [ "$sha" = "-" ] || [ -z "$sha" ]; then
    git fetch -q "$REMOTE" "+refs/tags/$p-build-$build:refs/tags/$p-build-$build" 2>/dev/null || true
    sha=$(git rev-parse -q --verify "refs/tags/$p-build-$build^{commit}") || {
      echo "::warning::$p-prod: $p $version is build $build, which has no Xcode Cloud run and no $p-build-$build tag — cannot tell which commit it is"
      status=1; continue
    }
  fi

  [ "$phased" != "PAUSED" ] || \
    echo "::warning::$p $version's phased release is PAUSED — $p-prod still points at it, since it is live for the users who got it"

  ./scripts/advance-app-prod-branch.sh "$p" "$version" "$sha" || status=1
done
exit $status
