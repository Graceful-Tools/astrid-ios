#!/bin/bash
# Is the astrid-core framework these apps link the one Xcode Cloud will link?
#
# Two ways to get it wrong, both silent until a TestFlight build behaves differently from the one
# that was tested:
#
# - a local `AstridCoreFFI.xcframework` built from something other than the revision
#   core/Cargo.toml pins — a local astrid-core checkout, or an older pin. Locally the app links
#   that; Xcode Cloud links the release.
# - no release at all: Package.swift still points at the placeholder, so Xcode Cloud cannot
#   resolve the package.
#
# Exit 0 when the two agree. Run by `npm run predeploy`.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PKG="$ROOT/Packages/AstridCore/Package.swift"
LOCAL="$ROOT/Packages/AstridCore/AstridCoreFFI.xcframework"
PINNED="$(sed -nE 's/^astrid-core = \{ git = "[^"]+", rev = "([0-9a-f]+)" \}/\1/p' "$ROOT/core/Cargo.toml")"

if grep -q 'releasedChecksum = "0\{64\}"' "$PKG"; then
  echo "RESULT: FAILED — no astrid-core framework is released for Xcode Cloud; run scripts/core/release-xcframework.sh <commit>" >&2
  exit 1
fi
if ! grep -q "core-${PINNED:0:7}/" "$PKG"; then
  echo "RESULT: FAILED — Package.swift links a release other than the pinned core ${PINNED:0:7}; run scripts/core/release-xcframework.sh ${PINNED:0:7}" >&2
  exit 1
fi
if [ -d "$LOCAL" ]; then
  BUILT="$(cat "$LOCAL/astrid-core-revision" 2>/dev/null || echo unknown)"
  if [ "$BUILT" != "$PINNED" ]; then
    echo "RESULT: FAILED — the local framework was built from astrid-core $BUILT, but the app pins $PINNED." >&2
    echo "  Run scripts/core/build-xcframework.sh (or delete $LOCAL to use the release)." >&2
    exit 1
  fi
fi
echo "RESULT: OK — astrid-core ${PINNED:0:7}, released and (if built locally) matching"
