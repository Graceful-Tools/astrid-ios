#!/bin/bash

# Generate the files a brand needs to be built as its OWN app — a second App Store record,
# installed beside Astrid rather than instead of it.
#
#   ./scripts/make-brand-variant.sh whitelabel-partner             # profile in ../astrid-web/brands/
#   ./scripts/make-brand-variant.sh path/to/acme.brand.json        # any profile, no astrid-web needed
#   ./scripts/make-brand-variant.sh acme --team ABCDE12345 --bundle-id com.acme.tasks
#
# apply-brand.sh edits Astrid's own plists in place: right for a quick look, wrong for a
# second app, which needs its own bundle ID, App Group, keychain group and associated
# domains, and must not share Family's TestFlight builds. The "Whitelabel" build
# configuration in the Xcode project points at the files this writes under Brands/Whitelabel/:
#
#   Info-iOS.plist / Info-Mac.plist / Info-Share.plist   copies of Astrid's, plus the brand
#   Whitelabel-iOS / -Mac / -Share .entitlements         copies, re-identified
#   variant.json                                         the identity last written (below)
#
# and rewrites the Whitelabel build configurations in project.pbxproj (team, bundle IDs, Mac
# product name) — nothing outside them.
#
# The variant's identity (AITD-515) comes from, in increasing precedence:
#   1. the defaults below — Graceful Tools' own Whitelabel app
#   2. the profile's optional "ios" block:
#        "ios": { "bundleId": "com.acme.tasks", "appGroup": "group.com.acme.tasks",
#                 "keychainGroup": "com.acme.tasks", "developmentTeam": "ABCDE12345",
#                 "displayName": "Acme Tasks" }
#   3. --bundle-id / --app-group / --keychain-group / --team / --display-name
# The Share extension is <bundleId>.Share; keychainGroup defaults to bundleId. The previous
# identity is read back from variant.json, which is how a second run finds what to replace.
#
# They are COPIES, so Astrid's files can move on without them. BrandVariantTests fails when a
# base plist gains a key the variant lacks — re-run this script and commit the result.
# scripts/test-make-brand-variant.sh is its self-test.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# shellcheck source=lib/find-web-repo.sh
source "$SCRIPT_DIR/lib/find-web-repo.sh"

PROFILE=""
OVERRIDES=()
while [[ $# -gt 0 ]]; do
    case $1 in
        --bundle-id)      OVERRIDES+=("bundleId=$2"); shift 2 ;;
        --app-group)      OVERRIDES+=("appGroup=$2"); shift 2 ;;
        --keychain-group) OVERRIDES+=("keychainGroup=$2"); shift 2 ;;
        --team)           OVERRIDES+=("developmentTeam=$2"); shift 2 ;;
        --display-name)   OVERRIDES+=("displayName=$2"); shift 2 ;;
        --help)           sed -n '3,33p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        -*)               echo "Unknown option: $1"; exit 1 ;;
        *)                PROFILE="$1"; shift ;;
    esac
done
PROFILE="${PROFILE:-whitelabel-partner}"

# A path is used as given, so a third party needs no astrid-web checkout; a bare name is
# looked up in the sibling one, as before.
if [[ -f "$PROFILE" ]]; then
    PROFILE_PATH="$(cd "$(dirname "$PROFILE")" && pwd)/$(basename "$PROFILE")"
else
    WEB_REPO="$(find_web_repo "$PROJECT_DIR")" || {
        echo "No such profile file, and no astrid-web checkout beside $(basename "$PROJECT_DIR") to look '$PROFILE' up in."
        echo "Pass the profile's path: $0 path/to/$PROFILE.brand.json"
        exit 1
    }
    PROFILE_PATH="$WEB_REPO/brands/${PROFILE}.brand.json"
    [[ -f "$PROFILE_PATH" ]] || { echo "No such brand profile: $PROFILE_PATH"; exit 1; }
fi

OUT="$PROJECT_DIR/Brands/Whitelabel"
mkdir -p "$OUT"
cp "$PROJECT_DIR/Info.plist"                              "$OUT/Info-iOS.plist"
cp "$PROJECT_DIR/Astrid Mac/Info.plist"                   "$OUT/Info-Mac.plist"
cp "$PROJECT_DIR/Astrid/Info.plist"                       "$OUT/Info-Share.plist"
cp "$PROJECT_DIR/Astrid App/Astrid App.entitlements"      "$OUT/Whitelabel-iOS.entitlements"
cp "$PROJECT_DIR/Astrid Mac/Astrid Mac.entitlements"      "$OUT/Whitelabel-Mac.entitlements"
cp "$PROJECT_DIR/Astrid/Astrid.entitlements"              "$OUT/Whitelabel-Share.entitlements"

# The brand's values and the partner domain, through the same code path as apply-brand.
BRAND_PLISTS="$OUT/Info-iOS.plist:$OUT/Info-Mac.plist" \
BRAND_ENTITLEMENTS="$OUT/Whitelabel-iOS.entitlements:$OUT/Whitelabel-Mac.entitlements" \
    "$SCRIPT_DIR/apply-brand.sh" "$PROFILE_PATH" >/dev/null

PB=/usr/libexec/PlistBuddy
set_string() { $PB -c "Delete :$2" "$1" 2>/dev/null || true; $PB -c "Add :$2 string $3" "$1"; }

python3 - "$OUT" "$PROFILE_PATH" "$PROJECT_DIR/Astrid App.xcodeproj/project.pbxproj" ${OVERRIDES[@]+"${OVERRIDES[@]}"} > "$OUT/.identity" <<'PY'
import json, os, re, sys
out, profile_path, pbxproj = sys.argv[1:4]

# Today's Whitelabel app. A profile without an ios block, and no arguments, reproduces it.
DEFAULTS = {"bundleId": "Graceful-Tools-Inc.Whitelabel", "appGroup": "group.gracefultools.whitelabel",
            "developmentTeam": "34K3P7PD2W", "displayName": "Whitelabel"}

profile = json.load(open(profile_path))
env = profile.get('env') or {}
ident = dict(DEFAULTS)
ident.update({k: str(v).strip() for k, v in (profile.get('ios') or {}).items() if str(v).strip()})
for arg in sys.argv[4:]:
    key, _, value = arg.partition('=')
    ident[key] = value
ident.setdefault('keychainGroup', ident['bundleId'])
name = (env.get('NEXT_PUBLIC_BRAND_NAME') or '').strip() or ident['displayName']
ident['brandName'] = name
apple = env.get('NEXT_PUBLIC_BRAND_ENABLE_AUTH_APPLE', 'true').strip().lower() != 'false'

record = os.path.join(out, 'variant.json')
previous = dict(DEFAULTS, keychainGroup=DEFAULTS['bundleId'], brandName=DEFAULTS['displayName'])
if os.path.isfile(record):
    previous.update(json.load(open(record)))

def rewrite(path, fn):
    text = open(path, encoding='utf-8').read()
    new = fn(text)
    if new != text:
        open(path, 'w', encoding='utf-8').write(new)

def entitlements(text):
    text = text.replace('group.gracefultools.astrid', ident['appGroup'])
    text = text.replace('$(AppIdentifierPrefix)Graceful-Tools-Inc.Astrid-App', '$(AppIdentifierPrefix)' + ident['keychainGroup'])
    # Drop Astrid's own domains; the partner's were added by apply-brand.
    text = re.sub(r'\n\s*<string>(applinks|webcredentials):(www\.)?astrid\.cc</string>', '', text)
    if not apple:   # the partner turns Sign in with Apple off; the profile never asks for it
        text = re.sub(r'\n\s*<key>com\.apple\.developer\.applesignin</key>\s*<array>.*?</array>', '', text, flags=re.S)
    return text

for e in ('Whitelabel-iOS.entitlements', 'Whitelabel-Mac.entitlements', 'Whitelabel-Share.entitlements'):
    rewrite(os.path.join(out, e), entitlements)

# The permission prompts are the first words a partner's user reads, and Astrid's name them
# (AITD-512). Text-level, so the rest of each copy stays byte-for-byte Astrid's;
# BrandVariantTests compares them back after the same swap.
def plist(text):
    text = re.sub(r'(<key>NS\w*UsageDescription</key>\s*<string>)([^<]*)(</string>)',
                  lambda m: m.group(1) + m.group(2).replace('Astrid', name) + m.group(3), text)
    # The Share extension's name, shown under its icon in the share sheet.
    text = re.sub(r'(<key>CFBundleDisplayName</key>\s*<string>)Astrid', lambda m: m.group(1) + name, text)
    # The Mac Services item (AITD-513): its menu title, and the port AppKit delivers it to,
    # which is named after the app. NSMessage is the Swift selector and stays addToAstrid.
    text = re.sub(r'(<key>NSMenuItem</key>\s*<dict>\s*<key>default</key>\s*<string>)([^<]*)',
                  lambda m: m.group(1) + m.group(2).replace('Astrid', ident['displayName']), text)
    return re.sub(r'(<key>NSPortName</key>\s*<string>)Astrid(</string>)',
                  lambda m: m.group(1) + ident['displayName'] + m.group(2), text)

for p in ('Info-iOS.plist', 'Info-Mac.plist', 'Info-Share.plist'):
    rewrite(os.path.join(out, p), plist)

# The Whitelabel build configurations, and only those. Each value is replaced where it still
# holds the PREVIOUS identity, so an unrelated setting that happens to share a configuration
# (a test target's own bundle ID) is never touched.
def q(value):   # pbxproj quoting, as Xcode writes it: a hyphen or a space is quoted
    return value if re.fullmatch(r'[A-Za-z0-9_./]+', value) else '"%s"' % value

def configuration(m):
    body = m.group(0)
    body = re.sub(r'(PRODUCT_BUNDLE_IDENTIFIER = )"?%s(\.[A-Za-z0-9.-]+)?"?;' % re.escape(previous['bundleId']),
                  lambda b: b.group(1) + q(ident['bundleId'] + (b.group(2) or '')) + ';', body)
    body = body.replace('DEVELOPMENT_TEAM = %s;' % previous['developmentTeam'], 'DEVELOPMENT_TEAM = %s;' % ident['developmentTeam'])
    body = re.sub(r'(INFOPLIST_KEY_CFBundleDisplayName = )[^;]*;', lambda b: b.group(1) + q(ident['displayName']) + ';', body)
    body = body.replace('PRODUCT_NAME = %s;' % q(previous['displayName']), 'PRODUCT_NAME = %s;' % q(ident['displayName']))
    body = body.replace('/%s.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/%s"' % (previous['displayName'], previous['displayName']),
                        '/%s.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/%s"' % (ident['displayName'], ident['displayName']))
    body = re.sub(r'(INFOPLIST_KEY_NS\w*UsageDescription = ")%s ' % re.escape(previous['brandName']),
                  lambda b: b.group(1) + name + ' ', body)
    return body

rewrite(pbxproj, lambda s: re.sub(r'/\* Whitelabel \*/ = \{\s*isa = XCBuildConfiguration;.*?name = Whitelabel;',
                                  configuration, s, flags=re.S))

with open(record, 'w') as f:
    json.dump(ident, f, indent=2, sort_keys=True)
    f.write('\n')
# For the shell: the plist identity keys, which PlistBuddy writes exactly as before.
print(ident['displayName']); print(ident['appGroup']); print('' if apple else ' (apple sign-in removed)')
PY

{ read -r DISPLAY_NAME; read -r APP_GROUP; read -r APPLE_NOTE; } < "$OUT/.identity"
rm -f "$OUT/.identity"

# Identity in the plists: name and App Group.
set_string "$OUT/Info-iOS.plist"   CFBundleDisplayName "$DISPLAY_NAME"
set_string "$OUT/Info-iOS.plist"   AppGroupIdentifier  "$APP_GROUP"
set_string "$OUT/Info-Share.plist" AppGroupIdentifier  "$APP_GROUP"

echo "  identity: $DISPLAY_NAME, $APP_GROUP$APPLE_NOTE"
echo "✓ Brands/Whitelabel regenerated from Astrid's files + $(basename "$PROFILE_PATH")"
