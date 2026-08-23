#!/bin/bash
#
# appstore-release.sh — build the iOS or Mac app ON THIS MACHINE and (optionally) upload it to
# App Store Connect, without Xcode Cloud.
#
# Why this exists: Xcode Cloud is the normal path (push iosdev/macdev/main and a workflow builds),
# but it has a monthly compute allotment. When that runs out every run is created and immediately
# CANCELED, and there is no API for it. A local archive + upload is the way through.
#
# SAFE BY DEFAULT: without --upload this only builds. Nothing reaches Apple.
#
#   ./scripts/appstore-release.sh ios              # build + export only, no upload
#   ./scripts/appstore-release.sh ios --upload     # build, upload, wait for the build to go VALID
#   ./scripts/appstore-release.sh mac --upload
#
# Options:
#   --upload        actually send the build to App Store Connect (otherwise: build only)
#   --skip-gate     don't run `npm run predeploy` first (it runs automatically before an upload)
#   --build N       pin the build number instead of asking App Store Connect for the next free one
#   --arch arm64    Mac only: skip the Intel slice (faster, but the result won't run on Intel Macs)
#   --no-wait       return as soon as the upload is accepted, without waiting for VALID
#
# Every run ends with one line starting `RESULT:` saying exactly what happened.
#
# Signing is automatic: -allowProvisioningUpdates plus the App Store Connect API key, which stands
# in for the Xcode account the CLI does not have. Credentials are read from .env.local BY NAME
# (APPLE_ASC_KEY_ID / APPLE_ASC_ISSUER_ID / APPLE_ASC_PRIVATE_KEY / APPLE_APP_STORE_APP_ID); the
# key is written mode-600 under build/ and deleted on every exit path. Nothing secret is printed.
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$PWD"

TARGET="${1:-}"; shift || true
UPLOAD=0; WAIT=1; SKIP_GATE=0; BUILD_NUM=""; ARCH=""
while [ $# -gt 0 ]; do
  case "$1" in
    --upload)    UPLOAD=1 ;;
    --dry-run)   UPLOAD=0 ;;          # the default; accepted so it can be stated explicitly
    --skip-gate) SKIP_GATE=1 ;;
    --no-wait)   WAIT=0 ;;
    --build)     BUILD_NUM="${2:-}"; shift ;;
    --arch)      ARCH="${2:-}"; shift ;;
    *) echo "RESULT: FAILED — unknown option \"$1\". Run: ./scripts/appstore-release.sh <ios|mac> [--upload]"; exit 2 ;;
  esac
  shift
done

case "$TARGET" in
  ios) SCHEME="Astrid App"; DESTINATION="generic/platform=iOS";   ARCHIVE_NAME="AstridiOS-AppStore" ;;
  mac) SCHEME="Astrid Mac"; DESTINATION="generic/platform=macOS"; ARCHIVE_NAME="AstridMac-AppStore" ;;
  *) echo "RESULT: FAILED — first argument must be ios or mac. Run: ./scripts/appstore-release.sh <ios|mac> [--upload]"; exit 2 ;;
esac

BUILD_DIR="$ROOT/build"
ARCHIVE="$BUILD_DIR/$ARCHIVE_NAME.xcarchive"
EXPORT_DIR="$BUILD_DIR/appstore-export-$TARGET"
LOG="$BUILD_DIR/appstore-release-$TARGET.log"

green() { printf "\033[0;32m%s\033[0m\n" "$1"; }
step()  { CURRENT_STEP="$1"; printf "\n\033[0;36m=== %s ===\033[0m\n" "$1"; }
CURRENT_STEP="starting up"

# Every exit path says what happened, in the same shape, so the outcome never has to be inferred
# from scrollback. The signing key is removed here too — success, failure or Ctrl-C alike.
KEY_FILE="$BUILD_DIR/.asc-key.p8"
finish() {
  local code=$?
  rm -f "$KEY_FILE" 2>/dev/null || true
  if [ "$code" -ne 0 ] && [ -z "${RESULT_PRINTED:-}" ]; then
    echo ""
    echo "RESULT: FAILED — $SCHEME, during: $CURRENT_STEP. Full output: $LOG"
  fi
  return 0
}
trap finish EXIT INT TERM

fail() { echo ""; echo "RESULT: FAILED — $1"; RESULT_PRINTED=1; exit 1; }
done_ok() { echo ""; echo "RESULT: OK — $1"; RESULT_PRINTED=1; }

# --- Credentials ------------------------------------------------------------------
step "Preflight"
[ -f .env.local ] || fail "no .env.local in astrid-ios. Fix: cp ../astrid-web/.env.local .env.local"
env_val() { awk -v k="$1=" 'index($0, k) == 1 { sub(/^[^=]*=/, ""); gsub(/^"|"$/, ""); print; exit }' .env.local; }
for n in APPLE_ASC_KEY_ID APPLE_ASC_ISSUER_ID APPLE_ASC_PRIVATE_KEY APPLE_APP_STORE_APP_ID; do
  grep -qE "^$n=." .env.local || fail "$n is missing from .env.local. Fix: cp ../astrid-web/.env.local .env.local"
done
KEY_ID=$(env_val APPLE_ASC_KEY_ID)
ISSUER=$(env_val APPLE_ASC_ISSUER_ID)
mkdir -p "$BUILD_DIR"
(umask 077; : > "$KEY_FILE")
# Match the APPLE_ASC_PRIVATE_KEY= prefix, not the first PEM block: .env.local holds other keys.
grep -E '^APPLE_ASC_PRIVATE_KEY=' .env.local | sed -E 's/^APPLE_ASC_PRIVATE_KEY=//; s/^"//; s/"$//' \
  | perl -pe 's/\\n/\n/g' > "$KEY_FILE"
green "✓ App Store Connect API key loaded"

# --- Versions ---------------------------------------------------------------------
# Read from the scheme's own build settings. Grepping project.pbxproj returns whichever target
# comes first in the file (the iOS app), which silently mislabels a Mac build.
SETTINGS=$(xcodebuild -scheme "$SCHEME" -destination "$DESTINATION" -showBuildSettings 2>/dev/null)
# awk, not `echo | grep -m1`: grep exits at the first match and closes the pipe, which makes echo
# die of SIGPIPE and takes the whole script down under `set -o pipefail`.
setting() { awk -v k=" $1 = " 'index($0, k) { sub(/.* = /, ""); print; exit }' <<<"$SETTINGS"; }
VERSION=$(setting MARKETING_VERSION)
PROJECT_BUILD=$(setting CURRENT_PROJECT_VERSION)
TEAM_ID=$(setting DEVELOPMENT_TEAM)
[ -n "$VERSION" ] || fail "could not read $SCHEME build settings — is Xcode installed and the project intact?"

if [ -z "$BUILD_NUM" ]; then
  BUILD_NUM=$(node scripts/asc-appstore.mjs next "$TARGET" --floor "${PROJECT_BUILD:-0}") \
    || fail "could not reach App Store Connect to pick a build number. Check the network and the APPLE_ASC_* values in .env.local"
fi
green "✓ $SCHEME $VERSION — build $BUILD_NUM"
if [ "$UPLOAD" = "1" ]; then echo "  Mode: UPLOAD (this build will be sent to Apple)"; else echo "  Mode: build only — nothing will be sent to Apple"; fi

# Apple accepts this build either way, but it only becomes a NEW App Store release under a version
# that is not already on sale. Say which one is happening before spending ten minutes on it.
VERSION_STATE=$(node scripts/asc-appstore.mjs versions "$TARGET" | awk -v v="$VERSION" '$1 == v { print $2; exit }')
if [ "$VERSION_STATE" = "READY_FOR_SALE" ]; then
  echo "  Note: $VERSION is already on sale, so this build lands in TestFlight."
  echo "        Shipping it as a new App Store release needs a higher MARKETING_VERSION first."
fi

# --- Quality gate -----------------------------------------------------------------
# An upload can never be taken back, so it does not happen on untested code. Build-only runs skip
# this: the archive below compiles everything anyway.
if [ "$UPLOAD" = "1" ] && [ "$SKIP_GATE" = "0" ]; then
  step "Quality gate (npm run predeploy)"
  npm run predeploy || fail "predeploy did not pass. Fix the build/tests before uploading, or re-run with --skip-gate if you know why it is failing."
  green "✓ Gate passed"
fi

rm -rf "$ARCHIVE" "$EXPORT_DIR"

# --- Archive ----------------------------------------------------------------------
# CURRENT_PROJECT_VERSION is overridden on the command line rather than edited into
# project.pbxproj: Xcode Cloud assigns its own build numbers (the run number), so the checked-in
# value is not the source of truth and editing it would only dirty the repo.
ARCH_ARGS=()
if [ -n "$ARCH" ]; then
  ARCH_ARGS=(ARCHS="$ARCH" ONLY_ACTIVE_ARCH=NO)
  echo "  Building $ARCH only"
fi

step "Archiving $SCHEME (several minutes)"
# `set +e` around the pipeline rather than a trailing `|| true`: `||` runs its own command, which
# resets PIPESTATUS, and xcodebuild's exit status is the only reliable verdict here (`-quiet`
# suppresses the "** ARCHIVE SUCCEEDED **" marker on success, so grepping for it reports every
# good archive as a failure).
set +e
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
  "${ARCH_ARGS[@]+"${ARCH_ARGS[@]}"}" 2>&1 | tee "$LOG" | grep -vE "^ +|^$"
ARCHIVE_RC=${PIPESTATUS[0]}
set -e
[ "$ARCHIVE_RC" -eq 0 ] || fail "the archive did not build. Search $LOG for 'error:'"
green "✓ Archived"

# --- Export (+ upload) ------------------------------------------------------------
if [ "$UPLOAD" = "1" ]; then DEST_KEY="upload"; else DEST_KEY="export"; fi
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

if [ "$UPLOAD" = "1" ]; then step "Uploading to App Store Connect"; else step "Exporting (no upload)"; fi
set +e
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportPath "$EXPORT_DIR" \
  -exportOptionsPlist "$BUILD_DIR/ExportOptions-appstore-$TARGET.plist" \
  -allowProvisioningUpdates \
  -authenticationKeyPath "$KEY_FILE" \
  -authenticationKeyID "$KEY_ID" \
  -authenticationKeyIssuerID "$ISSUER" 2>&1 | tee -a "$LOG" | grep -vE "^ +|^$"
EXPORT_RC=${PIPESTATUS[0]}
set -e
[ "$EXPORT_RC" -eq 0 ] || fail "the $([ "$UPLOAD" = 1 ] && echo upload || echo export) step failed. Search $LOG for 'error:'"

if [ "$UPLOAD" = "0" ]; then
  done_ok "$SCHEME $VERSION built and signed as build $BUILD_NUM. Nothing was uploaded — re-run with --upload to send it to Apple. Artifact: $EXPORT_DIR"
  exit 0
fi
green "✓ Upload accepted"

# --- Verify -----------------------------------------------------------------------
# An accepted upload is not yet an installable build: App Store Connect processes it afterwards
# and can still reject it. Nothing is called shipped before it reads VALID.
if [ "$WAIT" = "0" ]; then
  done_ok "$SCHEME $VERSION uploaded as build $BUILD_NUM, still processing. Check it with: node scripts/asc-appstore.mjs status $TARGET $BUILD_NUM"
  exit 0
fi

step "Waiting for App Store Connect to process the build (usually 5-15 minutes)"
node scripts/asc-appstore.mjs wait "$TARGET" "$BUILD_NUM" --timeout-min 45 \
  || fail "$SCHEME build $BUILD_NUM was uploaded but did not become VALID. Apple emails the reason; App Store Connect > TestFlight shows it too."

done_ok "$SCHEME $VERSION is live as build $BUILD_NUM — VALID in App Store Connect, installable from TestFlight. To put it on the App Store: App Store Connect > + Version, attach build $BUILD_NUM, add What's New, Submit for review."
