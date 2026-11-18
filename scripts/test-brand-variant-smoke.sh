#!/bin/bash
#
# Self-test for brand-variant-smoke.sh's checks on a built app (ADEV-109).
#
# The smoke itself builds and launches a client variant, which takes minutes and a simulator,
# so it runs as its own CI job. This file tests only the part that decides pass or fail. A
# fixture app with the scratch client's identity has to pass. Each way a variant can quietly
# stay Astrid's has to fail: the astrid.cc host, astrid://, Astrid's bundle id, and the shared
# App Group.

set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SMOKE="$ROOT/scripts/brand-variant-smoke.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
PB=/usr/libexec/PlistBuddy
FAILURES=0

make_app() { # dir — a fixture .app whose Info.plist is what the scratch client should build
    local app="$1"
    mkdir -p "$app/PlugIns/Share.appex"
    local p="$app/Info.plist"
    $PB -c "Add :CFBundleIdentifier string com.example.smoketasks" \
        -c "Add :CFBundleDisplayName string Smoke Tasks" \
        -c "Add :BrandName string Smoke" \
        -c "Add :AppGroupIdentifier string group.com.example.smoketasks" \
        -c "Add :BrandHost string tasks.smoke-client.invalid" \
        -c "Add :BrandURLScheme string smoketasks" \
        -c "Add :CFBundleURLTypes array" \
        -c "Add :CFBundleURLTypes:0 dict" \
        -c "Add :CFBundleURLTypes:0:CFBundleURLName string com.example.smoketasks" \
        -c "Add :CFBundleURLTypes:0:CFBundleURLSchemes array" \
        -c "Add :CFBundleURLTypes:0:CFBundleURLSchemes:0 string smoketasks" \
        -c "Add :BGTaskSchedulerPermittedIdentifiers array" \
        -c "Add :BGTaskSchedulerPermittedIdentifiers:0 string com.example.smoketasks.sync" \
        "$p" >/dev/null
    $PB -c "Add :CFBundleIdentifier string com.example.smoketasks.Share" "$app/PlugIns/Share.appex/Info.plist" >/dev/null
}

expect() { # label want(pass|fail) app
    if "$SMOKE" --verify "$3" >"$TMP/out.log" 2>&1; then got=pass; else got=fail; fi
    if [[ "$got" == "$2" ]]; then echo "  ✓ $1"; else echo "  ✗ $1 (wanted $2, got $got)"; sed 's/^/      /' "$TMP/out.log"; FAILURES=$((FAILURES + 1)); fi
}

variant() { # name plistbuddy-command [file] — a copy of the good app with one thing wrong
    cp -R "$TMP/good.app" "$TMP/$1.app"
    $PB -c "$2" "$TMP/$1.app/${3:-Info.plist}" >/dev/null
    echo "$TMP/$1.app"
}

echo "brand-variant-smoke.sh --verify"
make_app "$TMP/good.app"
expect "the scratch client's identity passes" pass "$TMP/good.app"
expect "the astrid.cc host fails" fail "$(variant host 'Set :BrandHost www.astrid.cc')"
expect "astrid:// as well fails" fail "$(variant scheme 'Add :CFBundleURLTypes:0:CFBundleURLSchemes:1 string astrid')"
expect "astrid:// instead fails" fail "$(variant scheme2 'Set :CFBundleURLTypes:0:CFBundleURLSchemes:0 astrid')"
expect "Whitelabel's bundle id fails" fail "$(variant bundle 'Set :CFBundleIdentifier Graceful-Tools-Inc.Whitelabel')"
expect "the shared App Group fails" fail "$(variant group 'Set :AppGroupIdentifier group.gracefultools.whitelabel')"
expect "Astrid's sync task id fails" fail "$(variant bg 'Set :BGTaskSchedulerPermittedIdentifiers:0 cc.astrid.app.sync')"
expect "a Share extension left on the old id fails" fail "$(variant share 'Set :CFBundleIdentifier Graceful-Tools-Inc.Whitelabel.Share' PlugIns/Share.appex/Info.plist)"
expect "a missing app fails" fail "$TMP/nothing.app"

[[ $FAILURES -eq 0 ]] || { echo "$FAILURES failure(s)"; exit 1; }
