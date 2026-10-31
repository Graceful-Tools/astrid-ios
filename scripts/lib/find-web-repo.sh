#!/bin/bash
# Locate the paired astrid-web checkout. Sourced by apply-brand.sh and check-brands.sh.
#
# Extracted because both had their own copy (task 97208a72), and the two would have had
# to be fixed together every time the worktree convention changed.
#
# Mirrors RepositoryLocator.siblingWebRepository() on the Swift side: an explicit checkout,
# a checkout nested inside this one (CI), the paired worktree, then the plain sibling.
#
# Usage:  WEB_REPO="$(find_web_repo "$PROJECT_DIR")" || echo "not found"

find_web_repo() {
    local project_dir="$1"
    local parent base suffix
    if [[ -n "${ASTRID_WEB_DIR:-}" ]]; then
        if [[ ! -f "$ASTRID_WEB_DIR/package.json" ]]; then
            echo "Invalid ASTRID_WEB_DIR: $ASTRID_WEB_DIR" >&2
            return 1
        fi
        (cd "$ASTRID_WEB_DIR" && pwd -P)
        return
    fi
    if [[ -f "$project_dir/astrid-web/package.json" ]]; then
        echo "$project_dir/astrid-web"
        return 0
    fi
    parent="$(dirname "$project_dir")"
    base="$(basename "$project_dir")"
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
