#!/bin/bash
#
# appstore-release.sh — archive the iOS or Mac app ON THIS MACHINE and upload it to
# App Store Connect, without Xcode Cloud.
#
# Why this exists: Xcode Cloud is the normal path (push iosdev/macdev/main and a workflow
# builds), but it has a monthly compute allotment. When that runs out every run is created and
# immediately CANCELED, and there is no API for it. A local archive + upload is the way through,
# and it is also faster when you just need one build now.
#
# Signing: automatic, with -allowProvisioningUpdates plus the App Store Connect API key, so
# xcodebuild can create/renew the distribution certificate and profile itself. The CLI has no
# Xcode account signed in; the API key is what stands in for one.
#
# Credentials come from .env.local by NAME — APPLE_ASC_KEY_ID, APPLE_ASC_ISSUER_ID,
# APPLE_ASC_PRIVATE_KEY, APPLE_APP_STORE_APP_ID. The key is written mode-600 under build/ and
# deleted on every exit path. Nothing secret is ever echoed.
#
# Usage:
#   ./scripts/appstore-release.sh ios                # archive → upload → wait for VALID
#   ./scripts/appstore-release.sh mac
#   ./scripts/appstore-release.sh ios --dry-run      # archive + export to build/, no upload
#   ./scripts/appstore-release.sh ios --build 912    # pin the build number
#   ./scripts/appstore-release.sh ios --no-wait      # upload, skip the VALID poll
#   ./scripts/appstore-release.sh mac --arch arm64   # Apple-silicon-only Mac build
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$PWD"

TARGET="${1:-}"; shift || true
DRY_RUN=0; WAIT=1; BUILD_NUM=""; ARCH=""
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY_RUN=1 ;;
    --no-wait) WAIT=0 ;;
    --build)   BUILD_NUM="${2:-}"; shift ;;
    --arch)    ARCH="${2:-}"; shift ;;
    *) echo "Unknown option: $1"; exit 2 ;;
  esac
  shift
done

case "$TARGET" in
  ios) SCHEME="Astrid App"; DESTINATION="generic/platform=iOS";   ARCHIVE_NAME="AstridiOS-AppStore" ;;
  mac) SCHEME="Astrid Mac"; DESTINATION="generic/platform=macOS"; ARCHIVE_NAME="AstridMac-AppStore" ;;
  *) echo "Usage: ./scripts/appstore-release.sh <ios|mac> [--dry-run] [--no-wait] [--build N] [--arch arm64]"; exit 2 ;;
esac

BUILD_DIR="$ROOT/build"
ARCHIVE="$BUILD_DIR/$ARCHIVE_NAME.xcarchive"
EXPORT_DIR="$BUILD_DIR/appstore-export-$TARGET"

green() { printf "\033[0;32m%s\033[0m\n" "$1"; }
red()   { printf "\033[0;31m%s\033[0m\n" "$1"; }
step()  { printf "\n\033[0;36m=== %s ===\033[0m\n" "$1"; }

# --- Credentials ------------------------------------------------------------------
# Kept out of shared /tmp, created mode-600 inside build/, removed on success, failure or Ctrl-C.
KEY_FILE="$BUILD_DIR/.asc-key.p8"
cleanup() { rm -f "$KEY_FILE" 2>/dev/null; return 0; }
trap cleanup EXIT INT TERM

step "Preflight"
[ -f .env.local ] || { red "No .env.local — copy it from ../astrid-web (it holds the ASC API key)."; exit 1; }
env_val() { grep -E "^$1=" .env.local | head -1 | sed -E "s/^$1=//; s/^\"//; s/\"$//"; }
KEY_ID=$(env_val APPLE_ASC_KEY_ID)
ISSUER=$(env_val APPLE_ASC_ISSUER_ID)
for n in APPLE_ASC_KEY_ID APPLE_ASC_ISSUER_ID APPLE_ASC_PRIVATE_KEY APPLE_APP_STORE_APP_ID; do
  grep -qE "^$n=." .env.local || { red "$n is missing from .env.local"; exit 1; }
done
mkdir -p "$BUILD_DIR"
(umask 077; : > "$KEY_FILE")
# Match the APPLE_ASC_PRIVATE_KEY= prefix, not the first PEM block: .env.local holds other keys.
grep -E '^APPLE_ASC_PRIVATE_KEY=' .env.local | sed -E 's/^APPLE_ASC_PRIVATE_KEY=//; s/^"//; s/"$//' \
  | perl -pe 's/\\n/\n/g' > "$KEY_FILE"
green "✓ App Store Connect API key loaded"

# --- Versions ---------------------------------------------------------------------
# Read from the scheme's own build settings: grepping project.pbxproj returns whichever target
# comes first in the file (the iOS app), which silently mislabels a Mac build.
SETTINGS=$(xcodebuild -scheme "$SCHEME" -destination "$DESTINATION" -showBuildSettings 2>/dev/null)
# awk, not `echo | grep -m1`: grep exits at the first match and closes the pipe, which makes echo
# die of SIGPIPE and takes the whole script down under `set -o pipefail`.
setting() { awk -v k=" $1 = " 'index($0, k) { sub(/.* = /, ""); print; exit }' <<<"$SETTINGS"; }
VERSION=$(setting MARKETING_VERSION)
PROJECT_BUILD=$(setting CURRENT_PROJECT_VERSION)
BUNDLE_ID=$(setting PRODUCT_BUNDLE_IDENTIFIER)
TEAM_ID=$(setting DEVELOPMENT_TEAM)
[ -n "$VERSION" ] && [ -n "$BUNDLE_ID" ] || { red "Could not read $SCHEME build settings"; exit 1; }

if [ -z "$BUILD_NUM" ]; then
  BUILD_NUM=$(node scripts/asc-appstore.mjs next "$TARGET" --floor "${PROJECT_BUILD:-0}")
fi
green "✓ $SCHEME $VERSION (build $BUILD_NUM) — $BUNDLE_ID, team $TEAM_ID"

# Apple will not accept a build under a marketing version that is already on sale as a NEW
# App Store release — it lands in TestFlight instead. Say so now rather than after the upload.
VERSION_STATE=$(node scripts/asc-appstore.mjs versions "$TARGET" | awk -v v="$VERSION" '$1 == v {print $2}' | head -1)
if [ "$VERSION_STATE" = "READY_FOR_SALE" ]; then
  echo ""
  echo "  Note: $VERSION is already READY_FOR_SALE on the App Store."
  echo "  This build will upload and be installable via TestFlight, but submitting it as a new"
  echo "  App Store release needs a higher MARKETING_VERSION in the project first."
fi

rm -rf "$ARCHIVE" "$EXPORT_DIR"

# --- Archive ----------------------------------------------------------------------
# CURRENT_PROJECT_VERSION is overridden on the command line rather than edited into
# project.pbxproj: Xcode Cloud assigns its own build numbers (the run number), so the checked-in
# value is not the source of truth and editing it just makes the repo dirty.
# The Mac target is universal (arm64 + x86_64) by default. --arch arm64 drops the Intel slice —
# useful when the x86_64 Release build trips a Swift optimizer crash, but it is a PRODUCT decision
# (an arm64-only build will not run on Intel Macs), so only pass it when the user has said to.
ARCH_ARGS=()
if [ -n "$ARCH" ]; then
  ARCH_ARGS=(ARCHS="$ARCH" ONLY_ACTIVE_ARCH=NO)
  echo "  Building $ARCH only"
fi

step "Archiving $SCHEME"
xcodebuild archive \
  -scheme "$SCHEME" \
  -destination "$DESTINATION" \
  -archivePath "$ARCHIVE" \
  -quiet \
  -allowProvisioningUpdates \
  -authenticationKeyPath "$KEY_FILE" \
  -authenticationKeyID "$KEY_ID" \
  -authenticationKeyIssuerID "$ISSUER" \
  CODE_SIGN_STYLE=Automatic \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  CURRENT_PROJECT_VERSION="$BUILD_NUM" \
  "${ARCH_ARGS[@]+"${ARCH_ARGS[@]}"}"
green "✓ Archived → $ARCHIVE"

# --- Export (+ upload) ------------------------------------------------------------
if [ "$DRY_RUN" = "1" ]; then DEST_KEY="export"; else DEST_KEY="upload"; fi
cat > "$BUILD_DIR/ExportOptions-appstore-$TARGET.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key><string>app-store-connect</string>
    <key>teamID</key><string>$TEAM_ID</string>
    <key>signingStyle</key><string>automatic</string>
    <key>destination</key><string>$DEST_KEY</string>
    <key>uploadSymbols</key><true/>
    <key>manageAppVersionAndBuildNumber</key><false/>
</dict>
</plist>
PLIST

if [ "$DRY_RUN" = "1" ]; then
  step "Exporting (dry run — no upload)"
else
  step "Exporting and uploading to App Store Connect"
fi
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportPath "$EXPORT_DIR" \
  -exportOptionsPlist "$BUILD_DIR/ExportOptions-appstore-$TARGET.plist" \
  -allowProvisioningUpdates \
  -authenticationKeyPath "$KEY_FILE" \
  -authenticationKeyID "$KEY_ID" \
  -authenticationKeyIssuerID "$ISSUER"

if [ "$DRY_RUN" = "1" ]; then
  echo ""
  green "✓ Dry run complete — artifact in $EXPORT_DIR (nothing was uploaded)"
  exit 0
fi
green "✓ Upload accepted by App Store Connect"

# --- Verify -----------------------------------------------------------------------
# An accepted upload is not an installable build: ASC processes it afterwards and can still
# reject it. Do not call anything shipped before it reads VALID.
if [ "$WAIT" = "1" ]; then
  step "Waiting for App Store Connect to finish processing"
  node scripts/asc-appstore.mjs wait "$TARGET" "$BUILD_NUM" --timeout-min 30
  echo ""
  green "✓ Build $BUILD_NUM ($VERSION) is VALID in App Store Connect"
else
  echo "Check processing with: node scripts/asc-appstore.mjs status $TARGET $BUILD_NUM"
fi

echo ""
echo "Next steps (App Store Connect, manual — they need release notes/screenshots/review info):"
echo "  1. App Store → + Version (if submitting a new release), attach build $BUILD_NUM"
echo "  2. Add What's New, then Add for Review → Submit"
echo "  Version states: node scripts/asc-appstore.mjs versions $TARGET"
