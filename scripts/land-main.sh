#!/bin/zsh
# land-main.sh — land local main on origin/main through a pull request, then build it.
#
#   npm run land            # PR, required checks, merge, then iosdev + macdev
#   npm run land -- --no-build   # main only (docs, scripts, a core lockfile bump)
#
# Since 2026-11-27 23:40 the `socket_gate` ruleset refuses a direct push to main until the
# required check "socket / socket-package-gate" has passed, and that check runs on pull requests
# only (ADEV-339). A scheduled run used to end with `git push origin main`; that now fails with
# GH013. This is the one plain command that replaces it (`npm run` is on the allowlist):
#
#   1. push main to a branch named after its newest commit, open a PR (or reuse one)
#   2. wait for the REQUIRED checks only; the long UI suites are not required and not waited on
#   3. merge with a merge commit, so the shas named in `**Awaiting build:**` lines stay real
#   4. fast-forward local main, then push iosdev and macdev to it (unless --no-build)
#
# One `RESULT:` line at the end. Env: LAND_GH (default gh; the test stubs it), LAND_REPO,
# LAND_WAIT_SECONDS (default 1200), LAND_POLL_SECONDS (default 20).
set -u

GH="${LAND_GH:-gh}"
REPO="${LAND_REPO:-Graceful-Tools/astrid-ios}"
WAIT="${LAND_WAIT_SECONDS:-1200}"
POLL="${LAND_POLL_SECONDS:-20}"
BUILD=1
[ "${1:-}" = "--no-build" ] && BUILD=0
fail() { print -r -- "RESULT: FAILED — $*"; exit 1; }
git_() { git -c core.fsmonitor=false "$@"; }

[ "$(git_ symbolic-ref -q --short HEAD)" = main ] || fail "not on main"
[ -z "$(git_ status --porcelain --untracked-files=no)" ] || fail "uncommitted changes; commit them first"
git_ fetch -q origin || fail "could not fetch origin"
git_ merge-base --is-ancestor origin/main main || fail "main has diverged from origin/main; rebase or merge it first"

ahead=$(git_ rev-list --count origin/main..main)
if [ "$ahead" -gt 0 ]; then
  subject=$(git_ log -1 --format=%s main)
  slug=$(print -r -- "$subject" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '-' | cut -c1-48 | sed 's/-*$//')
  branch="land/${slug:-main}-$(git_ rev-parse --short main)"
  git_ push -q origin "main:refs/heads/$branch" 2>/dev/null || fail "could not push $branch"
  pr=$("$GH" pr list --repo "$REPO" --head "$branch" --state open --json number --jq '.[0].number' 2>/dev/null)
  if [ -z "$pr" ]; then
    body=$(git_ log --format='- %s' origin/main..main)
    url=$("$GH" pr create --repo "$REPO" --base main --head "$branch" --title "$subject" \
      --body "$ahead commit(s), landed by scripts/land-main.sh:"$'\n\n'"$body") || fail "could not open a PR for $branch"
    pr=${url##*/}
  fi

  # Required checks only. `--required` with nothing reported yet exits non-zero, so poll.
  waited=0
  while :; do
    out=$("$GH" pr checks "$pr" --repo "$REPO" --required 2>/dev/null)
    if [ -n "$out" ] && ! print -r -- "$out" | grep -qE $'\t(pending|queued|in_progress)\t'; then
      print -r -- "$out" | grep -qE $'\t(fail|cancel|skipping)' && fail "PR #$pr: a required check did not pass: $(print -r -- "$out" | grep -E $'\t(fail|cancel)' | cut -f1 | tr '\n' ' ')"
      break
    fi
    [ "$waited" -ge "$WAIT" ] && fail "PR #$pr: required checks still not done after ${WAIT}s"
    sleep "$POLL"; waited=$((waited + POLL))
  done

  "$GH" pr merge "$pr" --repo "$REPO" --merge --delete-branch >/dev/null 2>&1 || fail "PR #$pr: merge refused"
  git_ fetch -q origin || fail "merged PR #$pr but could not fetch it"
  git_ merge -q --ff-only origin/main || fail "merged PR #$pr but local main would not fast-forward"
  landed="PR #$pr merged"
else
  landed="main already on origin"
fi

if [ "$BUILD" = 1 ]; then
  for b in iosdev macdev; do
    git_ push -q origin "main:refs/heads/$b" 2>/dev/null || fail "$landed; pushing $b failed (not a fast-forward?)"
    git_ update-ref "refs/heads/$b" main 2>/dev/null
  done
  print -r -- "RESULT: OK — $landed; main, iosdev and macdev at $(git_ rev-parse --short main)"
else
  print -r -- "RESULT: OK — $landed; main at $(git_ rev-parse --short main), no build"
fi
