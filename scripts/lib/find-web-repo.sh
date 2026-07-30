#!/bin/bash
# Locate the paired astrid-web checkout. Sourced by apply-brand.sh and check-brands.sh.
#
# Extracted because both had their own copy (task 97208a72), and the two would have had
# to be fixed together every time the worktree convention changed.
#
# Mirrors RepositoryLocator.siblingWebRepository() on the Swift side. When this repo is a
# git worktree (astrid-ios-<topic>) the matching web worktree is astrid-web-<topic>;
# prefer it, so a partner build from a feature worktree uses the brand on that branch.
#
# Usage:  WEB_REPO="$(find_web_repo "$PROJECT_DIR")" || echo "not found"

find_web_repo() {
    local project_dir="$1"
    local parent base suffix
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
