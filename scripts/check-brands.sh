#!/bin/bash

# Per-partner brand audit for iOS and Mac — task 97208a72.
#
# The counterpart of the web's `npm run check:brands`
# (tests/brands/brand-matrix.test.ts). Same idea, driven differently: Vitest can set env
# per test, but Info.plist is fixed for the life of a process, so on iOS the matrix has
# to be applied from OUTSIDE, once per profile.
#
# For each brands/*.brand.json in the paired astrid-web checkout (except astrid, which
# deliberately configures nothing):
#
#   1. apply the profile to every Info.plist
#   2. run BrandAuditTests — the assertions that only make sense on a partner build
#   3. revert
#
# What this catches that nothing else can: BrandAuditTests asserts that Info.plist
# configuration actually REACHES Brand, and that no Astrid value survives a rebrand. On
# an Astrid build every such assertion is vacuous — a reverted literal still compares
# equal to the configured value — so this is the only place a whitelabel regression is
# visible before a partner ships one.
#
#   ./scripts/check-brands.sh          # every profile
#   ./scripts/check-brands.sh acme     # just one

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

cd "$PROJECT_DIR"

PLISTS=("Info.plist" "Info-Debug.plist" "Astrid Mac/Info.plist")

# ALWAYS restore, however this exits — an interrupted run must never leave a partner's
# brand written into the working tree, where the next build would silently pick it up.
restore_plists() {
    for plist in "${PLISTS[@]}"; do
        [[ -f "$plist" ]] && git checkout -- "$plist" 2>/dev/null || true
    done
}
trap restore_plists EXIT INT TERM

# Refuse to start with uncommitted plist edits: the restore below is `git checkout --`,
# which would throw them away.
for plist in "${PLISTS[@]}"; do
    if [[ -f "$plist" ]] && ! git diff --quiet -- "$plist" 2>/dev/null; then
        echo -e "${RED}✗ $plist has uncommitted changes.${NC}"
        echo "  This script reverts plists with 'git checkout --', which would discard them."
        exit 1
    fi
done

find_web_repo() {
    local parent base suffix
    parent="$(dirname "$PROJECT_DIR")"
    base="$(basename "$PROJECT_DIR")"
    suffix=""
    [[ "$base" == astrid-ios* ]] && suffix="${base#astrid-ios}"
    for candidate in "astrid-web${suffix}" "astrid-web"; do
        [[ -f "$parent/$candidate/package.json" ]] && { echo "$parent/$candidate"; return 0; }
    done
    return 1
}

WEB_REPO="$(find_web_repo)" || {
    echo -e "${YELLOW}No astrid-web checkout beside $(basename "$PROJECT_DIR") — skipping.${NC}"
    echo "Brand profiles live in astrid-web/brands/."
    exit 0
}

if [[ -n "$1" ]]; then
    PROFILES=("$1")
else
    PROFILES=()
    for path in "$WEB_REPO"/brands/*.brand.json; do
        [[ -e "$path" ]] || continue
        name="$(basename "$path" .brand.json)"
        # astrid sets no environment at all — it is the regression guard proving an
        # unconfigured build behaves as it does today, so there is no partner to audit.
        [[ "$name" == "astrid" ]] && continue
        PROFILES+=("$name")
    done
fi

if [[ ${#PROFILES[@]} -eq 0 ]]; then
    echo -e "${YELLOW}No partner brand profiles to audit.${NC}"
    exit 0
fi

echo -e "${BLUE}=== Brand audit: ${PROFILES[*]} ===${NC}"
echo ""

FAILED=0
for profile in "${PROFILES[@]}"; do
    echo -e "${BLUE}── $profile ──${NC}"

    "$SCRIPT_DIR/apply-brand.sh" "$profile" >/dev/null

    set +e
    xcodebuild test \
        -scheme "Astrid App" \
        -destination "platform=iOS Simulator,name=iPhone 17" \
        -only-testing:"Astrid AppTests/BrandAuditTests" \
        -quiet > "/tmp/brand-audit-$profile.log" 2>&1
    RESULT=$?
    set -e

    restore_plists

    if [[ $RESULT -eq 0 ]]; then
        echo -e "${GREEN}  ✓ $profile audits clean${NC}"
    else
        echo -e "${RED}  ✗ $profile failed the brand audit${NC}"
        grep -E "error:|XCTAssert.*failed" "/tmp/brand-audit-$profile.log" | head -12 | sed 's/^/      /'
        echo "      full log: /tmp/brand-audit-$profile.log"
        FAILED=$((FAILED + 1))
    fi
    echo ""
done

echo "──────────────────────────────────────────"
if [[ $FAILED -eq 0 ]]; then
    echo -e "${GREEN}✓ Every brand profile audits clean.${NC}"
    exit 0
fi
echo -e "${RED}✗ $FAILED brand profile(s) failed.${NC}"
exit 1
