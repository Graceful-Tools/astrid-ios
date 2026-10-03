#!/bin/bash

# Generate the files a brand needs to be built as its OWN app — a second App Store record,
# installed beside Astrid rather than instead of it.
#
#   ./scripts/make-brand-variant.sh whitelabel-partner
#
# apply-brand.sh edits Astrid's own plists in place: right for a quick look, wrong for a
# second app, which needs its own bundle ID, App Group, keychain group and associated
# domains, and must not share Family's TestFlight builds. The "Whitelabel" build
# configuration in the Xcode project points at the files this writes under Brands/Whitelabel/:
#
#   Info-iOS.plist / Info-Mac.plist / Info-Share.plist   copies of Astrid's, plus the brand
#   Whitelabel-iOS / -Mac / -Share .entitlements         copies, re-identified
#
# They are COPIES, so Astrid's files can move on without them. BrandVariantTests fails when a
# base plist gains a key the variant lacks — re-run this script and commit the result.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
PROFILE="${1:-whitelabel-partner}"

# The variant's identity. One variant today; these become arguments when there is a second.
OUT="$PROJECT_DIR/Brands/Whitelabel"
BUNDLE_ID="Graceful-Tools-Inc.Whitelabel"
APP_GROUP="group.gracefultools.whitelabel"
DISPLAY_NAME="Whitelabel"

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
    "$SCRIPT_DIR/apply-brand.sh" "$PROFILE" >/dev/null

PB=/usr/libexec/PlistBuddy
set_string() { $PB -c "Delete :$2" "$1" 2>/dev/null || true; $PB -c "Add :$2 string $3" "$1"; }

# Identity: name, App Group, keychain group. Astrid's associated domains go — this app is
# not Astrid, and claiming astrid.cc links would steal them from the real one.
set_string "$OUT/Info-iOS.plist"   CFBundleDisplayName "$DISPLAY_NAME"
set_string "$OUT/Info-iOS.plist"   AppGroupIdentifier  "$APP_GROUP"
set_string "$OUT/Info-Share.plist" AppGroupIdentifier  "$APP_GROUP"
python3 - "$OUT" "$BUNDLE_ID" "$APP_GROUP" "$PROFILE" "$PROJECT_DIR" <<'PY'
import json, re, sys, os
out, bundle, group, profile, project = sys.argv[1:]
sys.path.insert(0, os.path.join(project, 'scripts', 'lib'))
web = None
for cand in [os.path.join(project, '..', 'astrid-web')] + [os.path.join(project, '..', d) for d in sorted(os.listdir(os.path.join(project, '..'))) if d.startswith('astrid-web')]:
    if os.path.isfile(os.path.join(cand, 'brands', f'{profile}.brand.json')):
        web = cand; break
env = json.load(open(os.path.join(web, 'brands', f'{profile}.brand.json')))['env']
apple = env.get('NEXT_PUBLIC_BRAND_ENABLE_AUTH_APPLE', 'true').strip().lower() != 'false'

def rewrite(name, fn):
    path = os.path.join(out, name)
    text = open(path, encoding='utf-8').read()
    open(path, 'w', encoding='utf-8').write(fn(text))

def identity(text):
    text = text.replace('group.gracefultools.astrid', group)
    text = text.replace('Graceful-Tools-Inc.Astrid-App', bundle)
    # Drop Astrid's own domains; the partner's were added by apply-brand.
    text = re.sub(r'\n\s*<string>(applinks|webcredentials):(www\.)?astrid\.cc</string>', '', text)
    if not apple:   # the partner turns Sign in with Apple off; the profile never asks for it
        text = re.sub(r'\n\s*<key>com\.apple\.developer\.applesignin</key>\s*<array>.*?</array>', '', text, flags=re.S)
    return text

for name in ('Whitelabel-iOS.entitlements', 'Whitelabel-Mac.entitlements', 'Whitelabel-Share.entitlements'):
    rewrite(name, identity)
print('  identity applied (apple sign-in kept)' if apple else '  identity applied (apple sign-in removed)')
PY

echo "✓ Brands/Whitelabel regenerated from Astrid's files + brands/$PROFILE.brand.json"
