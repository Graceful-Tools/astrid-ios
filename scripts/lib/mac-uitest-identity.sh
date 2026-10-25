#!/bin/bash
# Give a built Astrid.app its own identity before a Mac UI run (AITD-529).
#
# Built normally, the app under test carries the shipping bundle id, and macOS keys an app's
# sandbox container — its UserDefaults, Application Support, caches — by bundle id. So every UI
# run read and wrote the installed Astrid's saved settings: the journeys found the owner's saved
# user instead of the per-run account, and the run could leave the test account's name and email
# behind in the real app. The keychain and the local cache were already kept apart in code
# (`UITestSession.isUITesting`); UserDefaults is read in too many places to do the same.
#
# A different bundle id gets a different container, so nothing the run does can reach the real
# app's state. Signing is ad hoc with only what the suite needs: Sign in with Apple and the
# passkey domain are restricted entitlements tied to the shipping id and its profile, and the UI
# run injects its session rather than signing in.
#
# Usage: mac-uitest-identity.sh <path/to/Astrid.app>

set -euo pipefail

MAC_UITEST_BUNDLE_ID="Graceful-Tools-Inc.Astrid-App.uitest"

APP="${1:?usage: mac-uitest-identity.sh <path/to/Astrid.app>}"
LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $MAC_UITEST_BUNDLE_ID" "$APP/Contents/Info.plist"
codesign --force --deep --sign - --entitlements "$LIB_DIR/mac-uitest.entitlements" "$APP" 2>/dev/null

# Refuse to hand back an app that would still open the real container — the point of all this.
SIGNED_ID="$(codesign -dv "$APP" 2>&1 | sed -n 's/^Identifier=//p')"
if [[ "$SIGNED_ID" != "$MAC_UITEST_BUNDLE_ID" ]]; then
    echo "RESULT: FAILED — the UI-test app is signed as '$SIGNED_ID', not $MAC_UITEST_BUNDLE_ID; it would share the installed Astrid's settings." >&2
    exit 1
fi
echo "Mac UI-test app: $MAC_UITEST_BUNDLE_ID (own container, ad hoc signed)"
