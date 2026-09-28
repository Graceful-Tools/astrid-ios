#!/bin/bash
# Publish the astrid-core framework the apps pin, so Xcode Cloud can build them.
#
#   scripts/core/release-xcframework.sh <astrid-core commit>
#
# 1. Pins core/Cargo.toml to that commit (which must be on astrid-core's origin — Xcode Cloud and
#    everyone else fetch it from there).
# 2. Builds the XCFramework from exactly that revision, never a local checkout.
# 3. Uploads the zip as a release of astrid-ios, tagged `core-<short sha>`.
# 4. Points Packages/AstridCore/Package.swift at it by URL and checksum.
#
# Commit the three files it changes (core/Cargo.toml, core/Cargo.lock, Package.swift) with the
# change that needed the new core. Re-running for a revision already released reuses the release.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
REPO="Graceful-Tools/astrid-ios"
CORE_REPO="https://github.com/Graceful-Tools/astrid-core.git"
REV="${1:?usage: release-xcframework.sh <astrid-core commit>}"
export PATH="$HOME/.cargo/bin:$PATH"

# The full sha, confirmed to exist upstream.
FULL="$(git ls-remote "$CORE_REPO" | awk '{print $1}' | grep "^$REV" | head -1 || true)"
if [ -z "$FULL" ]; then
  FULL="$(cd "$ROOT/../astrid-core" 2>/dev/null && git rev-parse "$REV" 2>/dev/null || true)"
  if [ -z "$FULL" ] || ! (cd "$ROOT/../astrid-core" && git branch -r --contains "$FULL" | grep -q origin/); then
    echo "RESULT: FAILED — $REV is not on astrid-core's origin; push it first" >&2
    exit 1
  fi
fi
SHORT="${FULL:0:7}"
TAG="core-$SHORT"

sed -i '' -E "s|(astrid-core = \{ git = \"$CORE_REPO\", rev = \")[0-9a-f]+(\" \})|\1$FULL\2|" "$ROOT/core/Cargo.toml"
grep -q "rev = \"$FULL\"" "$ROOT/core/Cargo.toml" || { echo "RESULT: FAILED — could not pin core/Cargo.toml" >&2; exit 1; }
(cd "$ROOT/core" && cargo update -p astrid-core --precise "$FULL" >/dev/null 2>&1 || cargo update -p astrid-core >/dev/null)

"$ROOT/scripts/core/build-xcframework.sh" --zip
ZIP="$ROOT/build/core/AstridCoreFFI.xcframework.zip"
CHECKSUM="$(swift package compute-checksum "$ZIP")"

if gh release view "$TAG" --repo "$REPO" >/dev/null 2>&1; then
  # Same revision, rebuilt: the bytes differ run to run, so the checksum must follow the upload.
  gh release upload "$TAG" "$ZIP" --repo "$REPO" --clobber
else
  gh release create "$TAG" "$ZIP" --repo "$REPO" --title "astrid-core $SHORT" --latest=false \
    --notes "The astrid-core XCFramework the iOS and Mac apps link, built from Graceful-Tools/astrid-core@$FULL by scripts/core/release-xcframework.sh. Not an app release."
fi
URL="https://github.com/$REPO/releases/download/$TAG/AstridCoreFFI.xcframework.zip"

PKG="$ROOT/Packages/AstridCore/Package.swift"
sed -i '' -E "s|^let releasedURL = \".*\"|let releasedURL = \"$URL\"|; s|^let releasedChecksum = \".*\"|let releasedChecksum = \"$CHECKSUM\"|" "$PKG"

# The checksum SwiftPM will verify is the one of the bytes now on GitHub.
curl -sfL "$URL" -o "$ROOT/build/core/downloaded.zip"
[ "$(swift package compute-checksum "$ROOT/build/core/downloaded.zip")" = "$CHECKSUM" ] \
  || { echo "RESULT: FAILED — the uploaded zip does not match its checksum" >&2; exit 1; }

echo "RESULT: OK — $TAG ($CHECKSUM); commit core/Cargo.toml, core/Cargo.lock and Package.swift"
