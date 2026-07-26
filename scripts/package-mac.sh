#!/bin/bash
#
# package-mac.sh — build a signed, notarized, downloadable Astrid for Mac DMG.
#
# Produces build/dist/Astrid-Mac-<version>.dmg, ready to attach to a GitHub Release.
# The web download link points at the release asset (see astrid-web /download).
#
# Requirements (one-time):
#   • A "Developer ID Application" certificate in the login keychain.
#     Apple only lets the ACCOUNT HOLDER create one — do it in Xcode
#     (Settings › Accounts › Manage Certificates › + › Developer ID Application)
#     or at developer.apple.com with scripts/../~/Documents/astrid-developerid/devid.csr.
#   • ASC API credentials in .env.local (APPLE_ASC_KEY_ID / ISSUER_ID / PRIVATE_KEY) —
#     already present for Xcode Cloud; notarytool reuses them, so no app-specific password.
#
# Usage: npm run package:mac        (or ./scripts/package-mac.sh)
#        SKIP_NOTARIZE=1 ./scripts/package-mac.sh   # local smoke test, unsigned-ish
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$PWD"
BUILD_DIR="$ROOT/build"
ARCHIVE="$BUILD_DIR/AstridMac.xcarchive"
EXPORT_DIR="$BUILD_DIR/export"
DIST_DIR="$BUILD_DIR/dist"
SCHEME="Astrid Mac"

green() { printf "\033[0;32m%s\033[0m\n" "$1"; }
red()   { printf "\033[0;31m%s\033[0m\n" "$1"; }
step()  { printf "\n\033[0;36m=== %s ===\033[0m\n" "$1"; }

# --- Preflight: signing identity -------------------------------------------------
step "Preflight"
# `|| true`: no match is an expected state (cert not created yet), not a pipeline failure.
IDENTITY=$(security find-identity -v -p codesigning | grep "Developer ID Application" | head -1 | sed -E 's/.*"(.*)"/\1/' || true)
if [ -z "$IDENTITY" ]; then
  red "No 'Developer ID Application' certificate found in the keychain."
  echo "Create one (Account Holder only):"
  echo "  Xcode › Settings › Accounts › Manage Certificates › + › Developer ID Application"
  echo "  — or upload ~/Documents/astrid-developerid/devid.csr at"
  echo "    https://developer.apple.com/account/resources/certificates/add"
  exit 1
fi
green "✓ Signing identity: $IDENTITY"
TEAM_ID=$(echo "$IDENTITY" | sed -E 's/.*\(([A-Z0-9]+)\)$/\1/')

VERSION=$(grep -m1 'MARKETING_VERSION' "Astrid App.xcodeproj/project.pbxproj" | sed -E 's/.*= (.*);/\1/')
BUILD_NUM=$(grep -m1 'CURRENT_PROJECT_VERSION' "Astrid App.xcodeproj/project.pbxproj" | sed -E 's/.*= (.*);/\1/')
green "✓ Version $VERSION ($BUILD_NUM)"

rm -rf "$ARCHIVE" "$EXPORT_DIR"
mkdir -p "$DIST_DIR"

# --- Archive ---------------------------------------------------------------------
step "Archiving"
xcodebuild archive \
  -scheme "$SCHEME" \
  -destination "platform=macOS" \
  -archivePath "$ARCHIVE" \
  -quiet \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="$IDENTITY" \
  DEVELOPMENT_TEAM="$TEAM_ID"
green "✓ Archived"

# --- Export as Developer ID ------------------------------------------------------
step "Exporting (Developer ID)"
cat > "$BUILD_DIR/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key><string>developer-id</string>
    <key>teamID</key><string>$TEAM_ID</string>
    <key>signingStyle</key><string>manual</string>
    <key>destination</key><string>export</string>
</dict>
</plist>
PLIST

xcodebuild -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportPath "$EXPORT_DIR" \
  -exportOptionsPlist "$BUILD_DIR/ExportOptions.plist" \
  -quiet
APP="$EXPORT_DIR/$SCHEME.app"
[ -d "$APP" ] || { red "Export produced no .app"; exit 1; }
green "✓ Exported $(du -sh "$APP" | cut -f1)"

# --- Notarize --------------------------------------------------------------------
if [ "${SKIP_NOTARIZE:-0}" = "1" ]; then
  echo "SKIP_NOTARIZE=1 — skipping notarization (Gatekeeper will warn on other Macs)"
else
  step "Notarizing"
  # notarytool takes the same ASC API key Xcode Cloud uses; write it out briefly.
  KEY_FILE=$(mktemp /tmp/asc-XXXXXX.p8)
  trap 'rm -f "$KEY_FILE"' EXIT
  grep -E '^APPLE_ASC_PRIVATE_KEY=' .env.local | sed -E 's/^APPLE_ASC_PRIVATE_KEY=//; s/^"//; s/"$//' \
    | perl -pe 's/\\n/\n/g' > "$KEY_FILE"
  KEY_ID=$(grep -E '^APPLE_ASC_KEY_ID=' .env.local | cut -d= -f2- | tr -d '"')
  ISSUER=$(grep -E '^APPLE_ASC_ISSUER_ID=' .env.local | cut -d= -f2- | tr -d '"')

  ZIP="$BUILD_DIR/notarize.zip"
  rm -f "$ZIP"
  ditto -c -k --keepParent "$APP" "$ZIP"
  xcrun notarytool submit "$ZIP" \
    --key "$KEY_FILE" --key-id "$KEY_ID" --issuer "$ISSUER" \
    --wait --timeout 30m
  xcrun stapler staple "$APP"
  green "✓ Notarized + stapled"
  rm -f "$ZIP"
fi

# --- DMG -------------------------------------------------------------------------
step "Building DMG"
DMG="$DIST_DIR/Astrid-Mac-$VERSION.dmg"
STAGE="$BUILD_DIR/dmg-stage"
rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"      # drag-to-install affordance
hdiutil create -volname "Astrid" -srcfolder "$STAGE" -ov -format ULFO "$DMG" -quiet
rm -rf "$STAGE"

if [ "${SKIP_NOTARIZE:-0}" != "1" ]; then
  # The DMG itself is notarized too, so Gatekeeper is happy before the app is copied out.
  KEY_FILE=$(mktemp /tmp/asc-XXXXXX.p8)
  grep -E '^APPLE_ASC_PRIVATE_KEY=' .env.local | sed -E 's/^APPLE_ASC_PRIVATE_KEY=//; s/^"//; s/"$//' \
    | perl -pe 's/\\n/\n/g' > "$KEY_FILE"
  KEY_ID=$(grep -E '^APPLE_ASC_KEY_ID=' .env.local | cut -d= -f2- | tr -d '"')
  ISSUER=$(grep -E '^APPLE_ASC_ISSUER_ID=' .env.local | cut -d= -f2- | tr -d '"')
  codesign --force --sign "$IDENTITY" --timestamp "$DMG"
  xcrun notarytool submit "$DMG" --key "$KEY_FILE" --key-id "$KEY_ID" --issuer "$ISSUER" --wait --timeout 30m
  xcrun stapler staple "$DMG"
  rm -f "$KEY_FILE"
fi

step "Verifying"
spctl -a -vvv -t install "$DMG" 2>&1 | sed 's/^/  /' || true
codesign -dv --verbose=2 "$APP" 2>&1 | grep -E "Authority|TeamIdentifier|Timestamp" | sed 's/^/  /' || true

green "\n✓ $DMG ($(du -h "$DMG" | cut -f1))"
echo ""
echo "Publish it:"
echo "  gh release create mac-v$VERSION \"$DMG\" --title \"Astrid for Mac $VERSION\" --notes \"...\""
echo "The astrid.cc /download page resolves the latest release asset automatically."
