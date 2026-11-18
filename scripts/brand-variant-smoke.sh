#!/bin/bash
#
# brand-variant-smoke.sh: build a CLIENT's brand variant on a non-astrid.cc host, then launch it
# (ADEV-109).
#
# test-make-brand-variant.sh proves the script writes the right files, and BrandVariantTests
# proves the committed Whitelabel copies keep up with Astrid's plists. Before this, nothing
# compiled a variant with a non-default identity, and nothing ran one. A variant that wrote
# correct files and then failed to build, or crashed on launch because its App Group or URL type
# disagreed with the code, was only found when a partner tried it.
#
# This script:
#   1. makes a temporary git worktree of HEAD (the checkout it runs from is never touched)
#   2. writes a scratch client profile with its own bundle id, team, App Group, URL scheme, icon,
#      and a host that is not astrid.cc
#   3. runs make-brand-variant.sh for it
#   4. builds the `Whitelabel App` scheme for the iOS simulator, unsigned
#   5. checks the built app: bundle id, BrandHost, URL scheme, display name, App Group
#   6. installs and launches it on a simulator, then checks it is still running
#
# It does NOT sign in. The Whitelabel configuration is Release-like: the host is compiled in,
# and there is no debug_server_url and no ATS exception. So a variant can only reach a public
# HTTPS host that serves astrid-web. The scratch host here resolves nowhere, and the app has to
# boot to its sign-in screen regardless. Signing in against the partner's own server is a step
# the partner runs: see docs/BRAND_VARIANT.md, "Smoke-testing against your own server".
#
#   ./scripts/brand-variant-smoke.sh                     # build + launch
#   ./scripts/brand-variant-smoke.sh --no-launch         # build + check only
#   ./scripts/brand-variant-smoke.sh --verify <App.app>  # only the checks in step 5 (self-test)
#
# Env: ASTRID_SIMULATOR_NAME (default "iPhone 17"); ASTRID_KEEP_TEST_FIXTURES=1 keeps the
# worktree and build under TMPDIR.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# The scratch client. None of these is a real Apple team, App ID, or server.
SMOKE_BUNDLE_ID="com.example.smoketasks"
SMOKE_APP_GROUP="group.com.example.smoketasks"
SMOKE_TEAM="SMOKE00000"
SMOKE_DISPLAY_NAME="Smoke Tasks"
SMOKE_URL_SCHEME="smoketasks"
SMOKE_HOST="tasks.smoke-client.invalid"
SMOKE_BRAND_NAME="Smoke"

PLIST_BUDDY=/usr/libexec/PlistBuddy
FAILURES=0
pass() { echo "  ✓ $1"; }
fail() { echo "  ✗ $1"; FAILURES=$((FAILURES + 1)); }
plist() { "$PLIST_BUDDY" -c "Print :$2" "$1" 2>/dev/null; }
expect_eq() { # label actual expected
    if [[ "$2" == "$3" ]]; then pass "$1 = $3"; else fail "$1 is '${2}', expected '$3'"; fi
}

# Step 5. Kept separate so test-brand-variant-smoke.sh can run it against a fixture app.
verify_app() {
    local app="$1" info="$1/Info.plist"
    echo "Checking $(basename "$app")"
    [[ -f "$info" ]] || { fail "no Info.plist in $app"; return; }

    expect_eq "CFBundleIdentifier" "$(plist "$info" CFBundleIdentifier)" "$SMOKE_BUNDLE_ID"
    expect_eq "CFBundleDisplayName" "$(plist "$info" CFBundleDisplayName)" "$SMOKE_DISPLAY_NAME"
    expect_eq "BrandName" "$(plist "$info" BrandName)" "$SMOKE_BRAND_NAME"
    expect_eq "AppGroupIdentifier" "$(plist "$info" AppGroupIdentifier)" "$SMOKE_APP_GROUP"

    local host
    host="$(plist "$info" BrandHost)"
    expect_eq "BrandHost" "$host" "$SMOKE_HOST"
    case "$host" in
        *astrid.cc*) fail "BrandHost still names astrid.cc" ;;
    esac

    expect_eq "BrandURLScheme" "$(plist "$info" BrandURLScheme)" "$SMOKE_URL_SCHEME"
    local schemes
    schemes="$("$PLIST_BUDDY" -c "Print :CFBundleURLTypes" "$info" 2>/dev/null | grep -E '^ {12}[A-Za-z]' | tr -d ' ')"
    if grep -qx "$SMOKE_URL_SCHEME" <<< "$schemes"; then pass "registers $SMOKE_URL_SCHEME://"; else fail "does not register $SMOKE_URL_SCHEME:// (has: $(echo $schemes))"; fi
    if grep -qx "astrid" <<< "$schemes"; then fail "still registers astrid://"; else pass "does not register astrid://"; fi

    expect_eq "BGTaskSchedulerPermittedIdentifiers[0]" \
        "$(plist "$info" BGTaskSchedulerPermittedIdentifiers:0)" "$SMOKE_BUNDLE_ID.sync"

    local share="$app/PlugIns/Share.appex/Info.plist"
    if [[ -d "$app/PlugIns" ]]; then
        share="$(find "$app/PlugIns" -maxdepth 2 -name Info.plist | head -1)"
        expect_eq "Share extension bundle id" "$(plist "$share" CFBundleIdentifier)" "$SMOKE_BUNDLE_ID.Share"
    fi
}

if [[ "${1:-}" == "--verify" ]]; then
    verify_app "${2:?--verify needs the path of a built .app}"
    [[ $FAILURES -eq 0 ]] && { echo "RESULT: OK"; exit 0; }
    echo "RESULT: FAILED — $FAILURES check(s)"; exit 1
fi

LAUNCH=1
[[ "${1:-}" == "--no-launch" ]] && LAUNCH=0

TMP="$(mktemp -d "${TMPDIR:-/tmp}/brand-variant-smoke.XXXXXX")"
WORK="$TMP/repo"
cleanup() {
    git -C "$ROOT" worktree remove --force "$WORK" >/dev/null 2>&1 || true
    git -C "$ROOT" worktree prune >/dev/null 2>&1 || true
    if [[ "${ASTRID_KEEP_TEST_FIXTURES:-}" == "1" ]]; then echo "Kept $TMP"; else rm -rf "$TMP"; fi
}
trap cleanup EXIT

die() { echo "RESULT: FAILED — $1"; exit 1; }

echo "1. Worktree of $(git -C "$ROOT" rev-parse --short HEAD) in $WORK"
git -C "$ROOT" worktree add --detach "$WORK" HEAD >/dev/null 2>&1 || die "git worktree add failed"
# A fresh worktree resolving AstridCoreFFI by URL can deadlock on SwiftPM's artifact lock when the
# release zip is not cached. The checkout's local xcframework (which Package.swift prefers) avoids it.
if [[ -d "$ROOT/Packages/AstridCore/AstridCoreFFI.xcframework" ]]; then
    cp -R "$ROOT/Packages/AstridCore/AstridCoreFFI.xcframework" "$WORK/Packages/AstridCore/"
fi

echo "2. Scratch client profile ($SMOKE_BUNDLE_ID on $SMOKE_HOST)"
cp "$WORK/Astrid App/PartnerArt-iOS.xcassets/AppIcon-Whitelabel.appiconset/icon-1024x1024.png" "$TMP/smoke-icon.png"
cp "$WORK/Astrid App/PartnerArt-iOS.xcassets/whitelabel-logo.imageset/whitelabel-logo.png" "$TMP/smoke-mascot.png"
cat > "$TMP/smoke.brand.json" <<JSON
{
  "name": "Smoke client",
  "description": "Scratch profile for scripts/brand-variant-smoke.sh (ADEV-109). Not a real deployment.",
  "env": {
    "NEXT_PUBLIC_BRAND_NAME": "$SMOKE_BRAND_NAME",
    "NEXT_PUBLIC_BRAND_TITLE": "Smoke Tasks",
    "NEXT_PUBLIC_BRAND_DOMAIN": "$SMOKE_HOST",
    "NEXT_PUBLIC_BRAND_SUPPORT_EMAIL": "support@$SMOKE_HOST",
    "NEXT_PUBLIC_BRAND_ACCENT_COLOR": "#2f855a",
    "NEXT_PUBLIC_BRAND_APP_URL_SCHEME": "$SMOKE_URL_SCHEME",
    "NEXT_PUBLIC_BRAND_ENABLE_AUTH_GOOGLE": "false",
    "NEXT_PUBLIC_BRAND_ENABLE_AUTH_APPLE": "false"
  },
  "ios": {
    "bundleId": "$SMOKE_BUNDLE_ID",
    "appGroup": "$SMOKE_APP_GROUP",
    "developmentTeam": "$SMOKE_TEAM",
    "displayName": "$SMOKE_DISPLAY_NAME",
    "appIcon": "smoke-icon.png",
    "characterImage": "smoke-mascot.png"
  }
}
JSON

echo "3. make-brand-variant.sh"
(cd "$TMP" && env -u ASTRID_WEB_DIR "$WORK/scripts/make-brand-variant.sh" "$TMP/smoke.brand.json" >"$TMP/variant.log" 2>&1) \
    || { cat "$TMP/variant.log"; die "make-brand-variant.sh failed"; }

echo "4. Build Whitelabel App (simulator, unsigned)"
DERIVED="$TMP/DerivedData"
if ! xcodebuild build \
        -project "$WORK/Astrid App.xcodeproj" -scheme "Whitelabel App" -configuration Whitelabel \
        -destination "generic/platform=iOS Simulator" -derivedDataPath "$DERIVED" \
        CODE_SIGNING_ALLOWED=NO -quiet >"$TMP/build.log" 2>&1; then
    grep -E "error:|BUILD FAILED" "$TMP/build.log" | head -30
    die "the variant did not build (log: $TMP/build.log; ASTRID_KEEP_TEST_FIXTURES=1 keeps it)"
fi
APP="$(find "$DERIVED/Build/Products/Whitelabel-iphonesimulator" -maxdepth 1 -name '*.app' | head -1)"
[[ -n "$APP" ]] || die "build succeeded but produced no .app"

echo "5. Built app"
verify_app "$APP"
[[ $FAILURES -eq 0 ]] || die "$FAILURES check(s) on the built app"

if [[ $LAUNCH -eq 0 ]]; then echo "RESULT: OK — built and checked (launch skipped)"; exit 0; fi

echo "6. Launch on a simulator"
"$ROOT/scripts/prepare-ios-simulator.sh" >/dev/null || die "no simulator could be booted"
UDID="$(xcrun simctl list devices booted -j | node -e '
  const d = JSON.parse(require("fs").readFileSync(0, "utf8")).devices
  const name = process.env.ASTRID_SIMULATOR_NAME || "iPhone 17"
  const all = Object.values(d).flat()
  const hit = all.find(x => x.name === name) || all[0]
  if (hit) process.stdout.write(hit.udid)')"
[[ -n "$UDID" ]] || die "no booted simulator"

xcrun simctl uninstall "$UDID" "$SMOKE_BUNDLE_ID" >/dev/null 2>&1 || true
xcrun simctl install "$UDID" "$APP" || die "simctl install failed"
LAUNCHED="$(xcrun simctl launch "$UDID" "$SMOKE_BUNDLE_ID" 2>&1)" || { echo "$LAUNCHED"; die "simctl launch failed"; }
PID="${LAUNCHED##*: }"
sleep "${SMOKE_ALIVE_SECONDS:-8}"
if xcrun simctl spawn "$UDID" launchctl list 2>/dev/null | grep -q "UIKitApplication:$SMOKE_BUNDLE_ID"; then
    pass "still running ${SMOKE_ALIVE_SECONDS:-8}s after launch (pid $PID)"
else
    fail "exited within ${SMOKE_ALIVE_SECONDS:-8}s of launch"
    find ~/Library/Logs/DiagnosticReports -newer "$TMP/smoke.brand.json" -name '*.ips' 2>/dev/null | head -3
fi
xcrun simctl terminate "$UDID" "$SMOKE_BUNDLE_ID" >/dev/null 2>&1 || true
xcrun simctl uninstall "$UDID" "$SMOKE_BUNDLE_ID" >/dev/null 2>&1 || true

[[ $FAILURES -eq 0 ]] || die "the variant did not stay up after launch"
echo "RESULT: OK — a client variant built for $SMOKE_HOST and launched"
