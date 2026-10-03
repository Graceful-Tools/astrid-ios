#!/bin/bash
#
# test-ios-destination.sh — the default gate destination must ask for the newest iOS runtime
# (AITD-457).
#
# `name=iPhone 17` alone matches one simulator per installed runtime, and xcodebuild takes the
# first — iOS 26.2 on this machine. That runtime's libswift_Concurrency aborts in
# TaskLocal::StopLookupScope while running a main-actor deinit (swift_task_deinitOnExecutor), so
# PersistedDefaultsCachesTests and UserImageCacheTests crashed the suite there and passed on
# 26.5 and 27. The bug is Apple's runtime, not the app, and 26.5 fixed it.
set -u
cd "$(dirname "$0")/.."

dest="$(env -u ASTRID_IOS_DESTINATION -u ASTRID_SIMULATOR_NAME bash -c '. scripts/lib/ios-destination.sh; echo "$ASTRID_IOS_DESTINATION"')"
case "$dest" in
  *OS=latest*) ;;
  *) echo "✗ default iOS destination does not pin OS=latest: $dest"; exit 1 ;;
esac

override="$(ASTRID_IOS_DESTINATION='platform=iOS Simulator,id=X' bash -c '. scripts/lib/ios-destination.sh; echo "$ASTRID_IOS_DESTINATION"')"
if [ "$override" != 'platform=iOS Simulator,id=X' ]; then
  echo "✗ ASTRID_IOS_DESTINATION no longer overrides the default: $override"; exit 1
fi
echo "✓ ios-destination: default pins the newest runtime"
