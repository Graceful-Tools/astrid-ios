#!/bin/bash

# Apply a shared brand profile to the iOS and Mac Info.plist files — task 97208a72.
#
# The profile is `brands/<name>.brand.json` in the astrid-web repository. It is the
# SINGLE description of a brand for all three platforms; the mapping from its variables
# to the Info.plist keys `Brand` reads lives in Astrid App/Utilities/BrandProfile.swift,
# and BrandProfileTests fails the build if the two ever disagree.
#
#   ./scripts/apply-brand.sh acme            # apply
#   ./scripts/apply-brand.sh acme --dry-run  # show what would change
#   ./scripts/apply-brand.sh --reset         # remove every brand key (back to Astrid)
#
# Astrid itself needs NONE of this: every value defaults in Brand.swift, and
# brands/astrid.brand.json deliberately sets no environment at all. Running this is a
# partner-build step, not part of a normal build.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Every Info.plist a shipping target actually builds against. The iOS app uses a
# different file per configuration (INFOPLIST_FILE in project.pbxproj), so applying a
# brand to only one would rebrand a Release build and leave Debug reading Astrid — the
# kind of split nobody notices until a partner's TestFlight build looks wrong.
PLISTS=(
    "$PROJECT_DIR/Info.plist"           # Astrid App — Release
    "$PROJECT_DIR/Info-Debug.plist"     # Astrid App — Debug
    "$PROJECT_DIR/Astrid Mac/Info.plist"
)

# Keep in step with BrandProfile.keyMap. The Swift test parses Brand.swift and fails if
# a key it reads has no mapping, so the two cannot silently diverge.
BRAND_PLIST_KEYS=(
    BrandName BrandHost BrandAgentEmailDomain BrandSupportEmail BrandInboundTaskEmail
    BrandWordmark BrandSlogan BrandAgentName
    BrandAccentColor BrandAccentHoverColor BrandAccentTextColor
)

DRY_RUN=false
PROFILE=""
RESET=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run) DRY_RUN=true; shift ;;
        --reset)   RESET=true; shift ;;
        --help)
            sed -n '3,17p' "$0" | sed 's/^# \{0,1\}//'
            exit 0 ;;
        -*) echo "Unknown option: $1"; exit 1 ;;
        *)  PROFILE="$1"; shift ;;
    esac
done

# Locate the paired astrid-web checkout. When this repo is a git worktree
# (astrid-ios-<topic>) the matching web worktree is astrid-web-<topic>; prefer it, so a
# partner build from a feature worktree uses the brand on that branch.
find_web_repo() {
    local parent base suffix
    parent="$(dirname "$PROJECT_DIR")"
    base="$(basename "$PROJECT_DIR")"
    suffix=""
    [[ "$base" == astrid-ios* ]] && suffix="${base#astrid-ios}"

    for candidate in "astrid-web${suffix}" "astrid-web"; do
        if [[ -f "$parent/$candidate/package.json" ]]; then
            echo "$parent/$candidate"
            return 0
        fi
    done
    return 1
}

remove_all_keys() {
    local plist="$1"
    for key in "${BRAND_PLIST_KEYS[@]}"; do
        /usr/libexec/PlistBuddy -c "Delete :$key" "$plist" 2>/dev/null || true
    done
}

if [[ "$RESET" == "true" ]]; then
    echo -e "${BLUE}Removing every brand key — reverting to the Brand.swift defaults${NC}"
    for plist in "${PLISTS[@]}"; do
        [[ -f "$plist" ]] || continue
        if [[ "$DRY_RUN" == "true" ]]; then
            echo "  would clear $(basename "$(dirname "$plist")")/Info.plist"
        else
            remove_all_keys "$plist"
            echo -e "${GREEN}  ✓ cleared $(basename "$(dirname "$plist")")/Info.plist${NC}"
        fi
    done
    exit 0
fi

if [[ -z "$PROFILE" ]]; then
    echo -e "${RED}Usage: $0 <profile-name> [--dry-run]   |   $0 --reset${NC}"
    exit 1
fi

WEB_REPO="$(find_web_repo)" || {
    echo -e "${RED}No astrid-web checkout beside $(basename "$PROJECT_DIR")${NC}"
    echo "Brand profiles live in astrid-web/brands/. Clone it alongside this repo."
    exit 1
}

PROFILE_PATH="$WEB_REPO/brands/${PROFILE}.brand.json"
if [[ ! -f "$PROFILE_PATH" ]]; then
    echo -e "${RED}No such brand profile: $PROFILE_PATH${NC}"
    echo "Available:"
    ls "$WEB_REPO/brands/"*.brand.json 2>/dev/null | xargs -n1 basename | sed 's/^/  /'
    exit 1
fi

echo -e "${BLUE}=== Applying brand profile: $PROFILE ===${NC}"
echo "  from $PROFILE_PATH"
echo ""

# Map the profile's env to Info.plist keys. The mapping is duplicated from
# BrandProfile.keyMap because a shell script cannot import Swift; BrandProfileTests is
# what stops the Swift side drifting from what Brand actually reads, and the key list
# above is checked against this mapping by check-brand.sh.
MAPPED=$(python3 - "$PROFILE_PATH" <<'PY'
import json, sys

KEY_MAP = {
    "NEXT_PUBLIC_BRAND_NAME": "BrandName",
    "NEXT_PUBLIC_BRAND_DOMAIN": "BrandHost",
    "NEXT_PUBLIC_BRAND_SUPPORT_EMAIL": "BrandSupportEmail",
    "NEXT_PUBLIC_BRAND_INBOUND_TASK_EMAIL": "BrandInboundTaskEmail",
    "NEXT_PUBLIC_BRAND_WORDMARK": "BrandWordmark",
    "NEXT_PUBLIC_BRAND_SLOGAN": "BrandSlogan",
    "NEXT_PUBLIC_BRAND_ACCENT_COLOR": "BrandAccentColor",
    "NEXT_PUBLIC_BRAND_ACCENT_HOVER_COLOR": "BrandAccentHoverColor",
    "NEXT_PUBLIC_BRAND_ACCENT_TEXT_COLOR": "BrandAccentTextColor",
    "NEXT_PUBLIC_BRAND_AGENT_NAME": "BrandAgentName",
    "BRAND_AGENT_EMAIL_DOMAIN": "BrandAgentEmailDomain",
}

profile = json.load(open(sys.argv[1]))
env = profile.get("env") or {}
for variable, value in sorted(env.items()):
    key = KEY_MAP.get(variable)
    if not key:
        continue                      # web-only setting; not this platform's business
    value = str(value).strip()
    if value:
        print(f"{key}\t{value}")
PY
)

if [[ -z "$MAPPED" ]]; then
    echo -e "${YELLOW}This profile sets nothing the native apps consume.${NC}"
    echo "(brands/astrid.brand.json is deliberately empty — it proves the defaults are the defaults.)"
    exit 0
fi

for plist in "${PLISTS[@]}"; do
    [[ -f "$plist" ]] || continue
    target="$(basename "$(dirname "$plist")")/Info.plist"
    echo -e "${BLUE}$target${NC}"

    if [[ "$DRY_RUN" != "true" ]]; then
        # Clear first, so a profile that DROPS a key actually removes it rather than
        # leaving the previous brand's value behind.
        remove_all_keys "$plist"
    fi

    while IFS=$'\t' read -r key value; do
        [[ -z "$key" ]] && continue
        if [[ "$DRY_RUN" == "true" ]]; then
            echo "  would set $key = $value"
        else
            /usr/libexec/PlistBuddy -c "Add :$key string $value" "$plist" >/dev/null
            echo -e "${GREEN}  ✓ $key = $value${NC}"
        fi
    done <<< "$MAPPED"
    echo ""
done

if [[ "$DRY_RUN" == "true" ]]; then
    echo -e "${YELLOW}Dry run — nothing written.${NC}"
else
    echo -e "${GREEN}✓ Applied. Rebuild both targets; run './scripts/apply-brand.sh --reset' to revert.${NC}"
fi
