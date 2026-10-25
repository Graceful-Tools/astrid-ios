#!/bin/bash
#
# test-mac-uitest-identity.sh — the regression test for scripts/lib/mac-uitest-identity.sh
# (AITD-529).
#
# Mac UI runs launched the app under the shipping bundle id, so they shared the installed Astrid's
# container and read the owner's saved user. The helper re-identifies the built app; this pins
# that the result really carries the test id, is validly signed, and has none of the shipping
# entitlements — on a throwaway bundle, so nothing here needs Xcode or a build.
set -u
cd "$(dirname "$0")/.."

HELPER="$PWD/scripts/lib/mac-uitest-identity.sh"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
APP="$TMP/Astrid.app"
mkdir -p "$APP/Contents/MacOS"
cp /usr/bin/true "$APP/Contents/MacOS/Astrid"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>Graceful-Tools-Inc.Astrid-App</string>
<key>CFBundleExecutable</key><string>Astrid</string>
<key>CFBundlePackageType</key><string>APPL</string>
</dict></plist>
PLIST

fail=0
expect() {
  if [ "$2" = "$3" ]; then echo "✓ $1"; else echo "✗ $1"; echo "    want: $2"; echo "    got:  $3"; fail=1; fi
}

"$HELPER" "$APP" >/dev/null; rc=$?
expect "the helper succeeds" "0" "$rc"
expect "Info.plist carries the test bundle id" "Graceful-Tools-Inc.Astrid-App.uitest" \
  "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Contents/Info.plist")"
expect "the signature carries the test bundle id" "Graceful-Tools-Inc.Astrid-App.uitest" \
  "$(codesign -dv "$APP" 2>&1 | sed -n 's/^Identifier=//p')"
codesign --verify --deep "$APP" 2>/dev/null; expect "the signature verifies" "0" "$?"
ENTS="$(codesign -d --entitlements - "$APP" 2>/dev/null)"
expect "still sandboxed, so it gets a container of its own" "yes" \
  "$(grep -q com.apple.security.app-sandbox <<< "$ENTS" && echo yes || echo no)"
expect "no Sign in with Apple, passkey domain or keychain group" "no" \
  "$(grep -qE 'applesignin|associated-domains|keychain-access-groups|application-identifier' <<< "$ENTS" && echo yes || echo no)"

"$HELPER" "$TMP/missing.app" >/dev/null 2>&1; rc=$?
expect "a missing app fails rather than passing silently" "yes" "$([ "$rc" -ne 0 ] && echo yes || echo no)"

exit $fail
