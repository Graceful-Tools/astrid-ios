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
#   1. prepare branded copies of the plists and entitlements
#   2. apply them and run BrandAuditTests — assertions that only make sense on a partner build
#   3. restore only files that still match the audit's changes
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
source "$SCRIPT_DIR/lib/ios-destination.sh"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# shellcheck source=lib/find-web-repo.sh
source "$SCRIPT_DIR/lib/find-web-repo.sh"
source "$SCRIPT_DIR/lib/brand-audit-snapshot.sh"

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

cd "$PROJECT_DIR"

# apply-brand.sh writes a partner's domain into the entitlements as well as the plists.
PLISTS=("Info.plist" "Info-Debug.plist" "Astrid Mac/Info.plist"
        "Astrid App/Astrid App.entitlements" "Astrid Mac/Astrid Mac.entitlements"
        "Astrid Mac/Astrid Mac Direct.entitlements")

# Keep the existing clean-input requirement; snapshots also protect edits made during an audit.
for plist in "${PLISTS[@]}"; do
    if [[ -f "$plist" ]] && ! git diff --quiet -- "$plist" 2>/dev/null; then
        echo -e "${RED}✗ $plist has uncommitted changes.${NC}"
        echo "  Commit them first, then re-run."
        exit 1
    fi
done

WEB_REPO="$(find_web_repo "$PROJECT_DIR")" || {
    [[ -n "${ASTRID_WEB_DIR:-}" ]] && exit 1
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

finish_brand_audit() {
    local result=$?
    trap - EXIT INT TERM
    if [[ -n "${BRAND_AUDIT_DIR:-}" ]]; then
        brand_audit_restore || result=1
        brand_audit_dispose || result=1
    fi
    exit "$result"
}
trap finish_brand_audit EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
brand_audit_begin "${PLISTS[@]}"

FAILED=0
for profile in "${PROFILES[@]}"; do
    echo -e "${BLUE}── $profile ──${NC}"

    brand_audit_prepare
    BRAND_PLISTS="$(IFS=:; echo "${BRAND_AUDIT_EXPECTED[*]:0:3}")" \
    BRAND_ENTITLEMENTS="$(IFS=:; echo "${BRAND_AUDIT_EXPECTED[*]:3:3}")" \
        "$SCRIPT_DIR/apply-brand.sh" "$WEB_REPO/brands/$profile.brand.json" >/dev/null
    brand_audit_install

    IOS_LOG="$(mktemp "${TMPDIR:-/tmp}/brand-audit-ios.XXXXXXXX")"
    MAC_LOG="$(mktemp "${TMPDIR:-/tmp}/brand-audit-mac.XXXXXXXX")" || {
        rm -f -- "$IOS_LOG"
        exit 1
    }
    set +e
    xcodebuild test \
        -scheme "Astrid App" \
        -destination "$ASTRID_IOS_DESTINATION" \
        -only-testing:"Astrid AppTests/BrandAuditTests" \
        -collect-test-diagnostics never \
        -quiet > "$IOS_LOG" 2>&1
    IOS_RESULT=$?

    # Mac is audited SEPARATELY, not assumed. apply-brand.sh writes "Astrid Mac/
    # Info.plist" as its own file, and the Mac target has its own #if os(macOS) branch of
    # Theme with its own borderFocus — so "iOS is branded" says nothing about Mac.
    xcodebuild test \
        -scheme "Astrid Mac" \
        -destination "platform=macOS" \
        -only-testing:"Astrid MacTests/MacBrandAuditTests" \
        -quiet > "$MAC_LOG" 2>&1
    MAC_RESULT=$?
    set -e

    brand_audit_restore

    for platform in ios mac; do
        if [[ "$platform" == "ios" ]]; then RESULT=$IOS_RESULT; log="$IOS_LOG"
        else RESULT=$MAC_RESULT; log="$MAC_LOG"; fi
        if [[ $RESULT -eq 0 ]]; then
            echo -e "${GREEN}  ✓ $profile audits clean ($platform)${NC}"
            rm -f -- "$log"
        else
            echo -e "${RED}  ✗ $profile failed the brand audit ($platform)${NC}"
            # -quiet suppresses per-assertion output, so match the failure lines
            # xcodebuild still prints: "<file>:<line>: error: -[Class test] : ..."
            grep -E "error:|XCTAssert|Failing tests:|[[:space:]]+-\[" "$log" \
                | grep -v "^ *$" | head -12 | sed 's/^/      /'
            echo "      full log: $log"
            FAILED=$((FAILED + 1))
        fi
    done
    echo ""
done

echo "──────────────────────────────────────────"
if [[ $FAILED -eq 0 ]]; then
    echo -e "${GREEN}✓ Every brand profile audits clean.${NC}"
    exit 0
fi
echo -e "${RED}✗ $FAILED brand profile(s) failed.${NC}"
exit 1
