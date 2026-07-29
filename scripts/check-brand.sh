#!/bin/bash

# Brand-literal check for Astrid iOS / Mac — task 97208a72.
#
# The mirror of the web app's `npm run check:reuse` rule `hardcoded-brand-literal`.
#
# WHY A GREP AND NOT A UNIT TEST: brand values are compared by VALUE, and while Astrid
# is the brand every literal is equal to the configured value. A test asserting
# `Theme.accent == Brand.accentColor` therefore passes even if someone puts the literal
# back — verified by mutation. Only a source-level rule can catch that, and it only
# matters on a partner build, where nobody is looking.
#
# When adding a rule here, PLANT A VIOLATION AND CONFIRM IT FIRES. A rule that is green
# because its pattern is malformed is worse than no rule at all.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

cd "$PROJECT_DIR"

echo -e "${BLUE}=== Brand Literal Check (whitelabel) ===${NC}"
echo ""

ERRORS=0

# Source directories to scan. Tests are excluded: they legitimately assert on the
# Astrid defaults, which is the point of BrandTests.
SOURCE_DIRS=("Astrid App" "Astrid Mac")

# run_rule <id> <description> <fix> <ERE pattern> [exempt-basename ...]
run_rule() {
    local id="$1" description="$2" fix="$3" pattern="$4"
    shift 4

    local exclude_args=()
    for e in "$@"; do exclude_args+=(--exclude="$e"); done

    local hits
    hits=$(grep -rEn --include='*.swift' "${exclude_args[@]}" -e "$pattern" "${SOURCE_DIRS[@]}" 2>/dev/null || true)

    if [[ -z "$hits" ]]; then
        echo -e "${GREEN}  ✓ [$id] $description${NC}"
    else
        local count
        count=$(echo "$hits" | wc -l | tr -d ' ')
        echo -e "${RED}  ✗ [$id] $description: $count${NC}"
        echo -e "      fix: $fix"
        echo "$hits" | sed 's/^/        /'
        ERRORS=$((ERRORS + count))
    fi
}

# --- Rule: brand-accent-literal --------------------------------------------------
#
# The accent is the BRAND colour. Written out per theme variant it was 26 copies of
# Astrid blue, which made a partner theme a find-and-replace instead of a config change.
#
# Exempt:
#   Brand.swift      — where the default is DEFINED
#   MacListEditSheet — the list-colour palette users pick FROM; not the brand
#   Project.swift / TaskList.swift / ListService.swift / ListImageHelper.swift /
#   ReminderPresenter.swift / ShareListView.swift / InlineListsPicker.swift /
#   ListImageView.swift / ReminderView.swift / ImagePickerView.swift /
#   CompactTaskRow.swift
#                    — the DEFAULT LIST COLOUR sent by the server. A client-side
#                      fallback that disagrees with the server's default is a bug, so
#                      these track the protocol, not the brand.
run_rule "brand-accent-literal" \
    "Hardcoded brand accent (Astrid blue) outside Brand.swift" \
    "Use Brand.accentColor / Theme.accent (Astrid App/Utilities/Brand.swift)." \
    '59/255,[[:space:]]*green:[[:space:]]*130/255|Color\(hex:[[:space:]]*"#?3b82f6"' \
    "Brand.swift" \
    "MacListEditSheet.swift" \
    "Project.swift" \
    "TaskList.swift" \
    "ListService.swift" \
    "ListImageHelper.swift" \
    "ReminderPresenter.swift" \
    "ShareListView.swift" \
    "InlineListsPicker.swift" \
    "ListImageView.swift" \
    "ReminderView.swift" \
    "ImagePickerView.swift" \
    "CompactTaskRow.swift"

echo ""
echo "──────────────────────────────────────────"
if [[ $ERRORS -eq 0 ]]; then
    echo -e "${GREEN}✓ No brand-literal violations found.${NC}"
    exit 0
fi
echo -e "${RED}✗ $ERRORS brand-literal violation(s).${NC}"
exit 1
