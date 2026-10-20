#!/bin/bash
# Self-test for make-brand-variant.sh (AITD-515).
#
# The variant's identity — bundle ID, App Group, keychain group, team, name — used to be
# baked into the script, so a third party with their own Apple team had to hand-edit the
# pbxproj. This runs the script in a scratch copy of the repo, with NO astrid-web beside it
# (the profile is passed by path), and checks:
#
#   1. no `ios` block → the committed Whitelabel files come back byte-for-byte
#   2. an `ios` block → every identity value lands in the plists, entitlements and the
#      Whitelabel build configurations, and nothing outside them moves
#   3. arguments beat the profile
#   4. going back to the defaults restores the committed files (the previous identity is
#      recorded in Brands/Whitelabel/variant.json, so a second rewrite can find it)

set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
FAILURES=0

pass() { echo "  ✓ $1"; }
fail() { echo "  ✗ $1"; FAILURES=$((FAILURES + 1)); }
check() { if eval "$2"; then pass "$1"; else fail "$1"; fi; }

PARTNER="$(ls "$ROOT"/../astrid-web*/brands/whitelabel-partner.brand.json 2>/dev/null | head -1)"
if [[ -z "$PARTNER" ]]; then
    echo "No astrid-web checkout with brands/whitelabel-partner.brand.json beside this repo — skipping."
    exit 0
fi

WORK="$TMP/repo"
for f in Info.plist "Astrid Mac/Info.plist" "Astrid/Info.plist" \
         "Astrid App/Astrid App.entitlements" "Astrid Mac/Astrid Mac.entitlements" "Astrid/Astrid.entitlements" \
         "Astrid App.xcodeproj/project.pbxproj" \
         scripts/make-brand-variant.sh scripts/apply-brand.sh scripts/lib/find-web-repo.sh; do
    mkdir -p "$WORK/$(dirname "$f")"
    cp "$ROOT/$f" "$WORK/$f"
done
cp -R "$ROOT/Brands" "$WORK/Brands"
cp "$PARTNER" "$TMP/partner.brand.json"

# The partner profile plus an ios block — a third party's own identity.
python3 - "$PARTNER" "$TMP/acme.brand.json" <<'PY'
import json, sys
profile = json.load(open(sys.argv[1]))
profile["env"]["NEXT_PUBLIC_BRAND_NAME"] = "Acme"
profile["ios"] = {"bundleId": "com.acme.tasks", "appGroup": "group.com.acme.tasks",
                  "keychainGroup": "com.acme.shared", "developmentTeam": "ABCDE12345",
                  "displayName": "Acme Tasks"}
json.dump(profile, open(sys.argv[2], "w"), indent=2)
PY

# Every Whitelabel build configuration, and the project with them removed.
whitelabel_blocks() { python3 -c '
import re, sys
s = open(sys.argv[1]).read()
blocks = re.findall(r"/\* Whitelabel \*/ = \{\s*isa = XCBuildConfiguration;.*?name = Whitelabel;", s, re.S)
print("\n".join(blocks) if sys.argv[2] == "in" else re.sub(r"/\* Whitelabel \*/ = \{\s*isa = XCBuildConfiguration;.*?name = Whitelabel;", "", s, flags=re.S))
' "$1" "$2"; }

same_as_committed() {
    diff -r -x variant.json "$ROOT/Brands/Whitelabel" "$WORK/Brands/Whitelabel" >/dev/null &&
    cmp -s "$ROOT/Astrid App.xcodeproj/project.pbxproj" "$WORK/Astrid App.xcodeproj/project.pbxproj"
}

run() { (cd "$TMP" && "$WORK/scripts/make-brand-variant.sh" "$@" >"$TMP/out.log" 2>&1) || { cat "$TMP/out.log"; return 1; }; }

echo "1. no ios block, profile by path, no astrid-web beside the repo"
check "runs" 'run "$TMP/partner.brand.json"'
check "reproduces the committed files" same_as_committed

echo "2. an ios block"
check "runs" 'run "$TMP/acme.brand.json"'
PB="$WORK/Astrid App.xcodeproj/project.pbxproj"
IN="$(whitelabel_blocks "$PB" in)"
check "no Graceful Tools identity left in the Whitelabel configurations" \
      '! grep -qE "34K3P7PD2W|Graceful-Tools-Inc\.Whitelabel" <<< "$IN"'
check "team" 'grep -q "DEVELOPMENT_TEAM = ABCDE12345;" <<< "$IN"'
check "app and Share bundle IDs" \
      'grep -q "PRODUCT_BUNDLE_IDENTIFIER = com.acme.tasks;" <<< "$IN" && grep -q "PRODUCT_BUNDLE_IDENTIFIER = com.acme.tasks.Share;" <<< "$IN"'
check "Mac product name and test host" \
      'grep -q "PRODUCT_NAME = \"Acme Tasks\";" <<< "$IN" && grep -q "/Acme Tasks.app/\$(BUNDLE_EXECUTABLE_FOLDER_PATH)/Acme Tasks\"" <<< "$IN"'
check "Mac permission prompts" 'grep -q "\"Acme links your lists" <<< "$IN"'
check "nothing outside the Whitelabel configurations moved" \
      '[[ "$(whitelabel_blocks "$PB" out)" == "$(whitelabel_blocks "$ROOT/Astrid App.xcodeproj/project.pbxproj" out)" ]]'
V="$WORK/Brands/Whitelabel"
check "display name and App Group" \
      '[[ "$(/usr/libexec/PlistBuddy -c "Print :CFBundleDisplayName" "$V/Info-iOS.plist")" == "Acme Tasks" ]] &&
       [[ "$(/usr/libexec/PlistBuddy -c "Print :AppGroupIdentifier" "$V/Info-iOS.plist")" == group.com.acme.tasks ]] &&
       [[ "$(/usr/libexec/PlistBuddy -c "Print :AppGroupIdentifier" "$V/Info-Share.plist")" == group.com.acme.tasks ]]'
check "entitlements carry the App Group and keychain group" \
      'grep -q "group.com.acme.tasks" "$V/Whitelabel-iOS.entitlements" && grep -q "group.com.acme.tasks" "$V/Whitelabel-Share.entitlements" &&
       grep -q "(AppIdentifierPrefix)com.acme.shared<" "$V/Whitelabel-iOS.entitlements" && ! grep -rq "gracefultools.whitelabel" "$V"'
check "Services item is named for the app" \
      '[[ "$(/usr/libexec/PlistBuddy -c "Print :NSServices:0:NSPortName" "$V/Info-Mac.plist")" == "Acme Tasks" ]]'
check "permission prompts name the brand" 'grep -q "Acme uses your camera" "$V/Info-iOS.plist"'

echo "3. arguments beat the profile"
check "runs" 'run "$TMP/acme.brand.json" --team ZZZZZ99999 --bundle-id com.acme.other'
IN="$(whitelabel_blocks "$PB" in)"
check "argument team and bundle ID" \
      'grep -q "DEVELOPMENT_TEAM = ZZZZZ99999;" <<< "$IN" && grep -q "PRODUCT_BUNDLE_IDENTIFIER = com.acme.other.Share;" <<< "$IN" && ! grep -q ABCDE12345 <<< "$IN"'

echo "4. back to the defaults"
check "runs" 'run "$TMP/partner.brand.json"'
check "reproduces the committed files" same_as_committed

echo ""
if [[ $FAILURES -eq 0 ]]; then echo "✓ make-brand-variant.sh self-test passed"; exit 0; fi
echo "✗ make-brand-variant.sh self-test: $FAILURES failure(s)"; exit 1
