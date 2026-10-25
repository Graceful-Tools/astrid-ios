#!/bin/bash
# Mint a per-run test account and hand it to a UI suite as `UITestSession.plist` (AITD-529).
#
# Sourced by `run-tests.sh --ui` (iOS) and `run-mac-tests.sh --ui` (Mac). It lived inside
# run-tests.sh, which is why the Mac suite had no signed-in path: there was nothing for it to
# call. The caller sets PROJECT_DIR and SESSION_PLIST — the plist goes in the suite's own folder,
# whose synchronized group copies it into that test bundle — then calls `write_uitest_session`
# and traps `cleanup_uitest_session` on EXIT.

: "${RED:=\033[0;31m}" "${GREEN:=\033[0;32m}" "${YELLOW:=\033[1;33m}" "${BLUE:=\033[0;34m}" "${NC:=\033[0m}"

# Hand the UI suite a session — for an account of this run's own (AITD-527).
#
# Not an environment variable: xcodebuild forwards neither the plain variable nor the
# TEST_RUNNER_-prefixed build setting to the xctrunner process (measured 2026-08-16), so the
# first attempt at this silently injected nothing and the whole suite ran signed out while
# reporting success. A file inside the test bundle does arrive. See UITestLaunch.swift.
#
# The file is gitignored and rewritten every run — a NextAuth session expires after 30 days,
# and a committed token would fail in a way indistinguishable from the skip it replaced.
#
# **A run gets its own account.** Every runner used to mint the one shared uitest@astrid.cc, and
# each mint wipes and reseeds it — so a CI job minting mid-run deleted a local run's tasks
# under it. `uitest-account.ts --run <id>` (AWTD-1328) mints uitest+<id>@astrid.cc with its own
# lists and fixtures and prints one JSON document; the fixture ids go into the plist next to
# the cookie, so a test can name a task by id and check it on the server (UITestAPI). The
# EXIT trap deletes the account; a run killed before the trap fires is reaped by the next
# mint after 24 hours.
#
# ASTRID_UITEST_COOKIE still works, for the shared account, with no fixture ids.
# ASTRID_UITEST_BASE_URL points the run at another server (`-uiTestBaseURL`), e.g. staging.
ASTRID_WEB_DIR="${ASTRID_WEB_DIR:-$PROJECT_DIR/../astrid-web}"
UITEST_RUN_ID=""

# A run id is 1-48 chars of [a-z0-9-], starts with a letter or digit, never ends in -owner.
uitest_run_id() {
    if [[ -n "${ASTRID_UITEST_RUN_ID:-}" ]]; then
        echo "$ASTRID_UITEST_RUN_ID"
    elif [[ -n "${GITHUB_RUN_ID:-}" ]]; then
        echo "gha-${GITHUB_RUN_ID}-${GITHUB_RUN_ATTEMPT:-1}"
    else
        echo "local-$$-$(date +%s)"
    fi
}

# tsx does not read .env.local on its own, and without it the mint dies on "NEXTAUTH_SECRET
# missing". CI has no .env.local (the secrets arrive as environment), and --env-file on a
# missing file is an error, so pass it only when the file is there.
uitest_account() {
    local env_flag=()
    [[ -f "$ASTRID_WEB_DIR/.env.local" ]] && env_flag=(--env-file=.env.local)
    (cd "$ASTRID_WEB_DIR" && npx tsx "${env_flag[@]}" scripts/uitest-account.ts "$@")
}

write_uitest_session() {
    local cookie="${ASTRID_UITEST_COOKIE:-}"
    local fixtures=""

    if [[ -z "$cookie" && -d "$ASTRID_WEB_DIR" ]]; then
        local run_id minted
        run_id="$(uitest_run_id)"
        echo -e "${BLUE}Minting a test account for run ${run_id}...${NC}"
        minted="$(uitest_account --run "$run_id" 2>/tmp/uitest_mint.log)" || minted=""
        if [[ -n "$minted" ]]; then
            UITEST_RUN_ID="$run_id"
            cookie="$(printf '%s' "$minted" | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{try{process.stdout.write(JSON.parse(s).cookie||"")}catch{}})')"
            fixtures="$(printf '%s' "$minted" | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{try{process.stdout.write(JSON.stringify(JSON.parse(s).fixtures||null))}catch{}})')"
        else
            tail -5 /tmp/uitest_mint.log >&2 || true
        fi
    fi

    if [[ -z "$cookie" ]]; then
        # A hard stop, not a warning. Signed out, every test that needs an account skips
        # itself and the run still reports "✓ UI tests passed (28 passed, 36 skipped)" —
        # green while asserting nothing, which is the exact failure this account exists to
        # end. It went unnoticed for a day because the warning scrolled past in a ten-minute
        # run and the summary said passed (task b86c97c5).
        echo -e "${RED}✗ No test-account session available — refusing to run the UI suite.${NC}"
        echo "  Signed out, every test that needs an account skips and the run reports green."
        echo "  Mint one: cd ../astrid-web && npx tsx scripts/uitest-account.ts --run <id>"
        echo "  Or pass one: ASTRID_UITEST_COOKIE=... npm run test:ui"
        rm -f "$SESSION_PLIST"
        exit 1
    fi

    # GitHub masks the cookie only once it has been told to.
    [[ "${GITHUB_ACTIONS:-}" == "true" ]] && echo "::add-mask::${cookie}"

    # Built as JSON and converted, because a fixtures document full of quotes and spaces does
    # not survive PlistBuddy's command parsing.
    local json_tmp
    json_tmp="$(mktemp -t uitest-session)"
    UITEST_COOKIE="$cookie" UITEST_FIXTURES="$fixtures" UITEST_RUN="$UITEST_RUN_ID" \
    UITEST_BASE_URL="${ASTRID_UITEST_BASE_URL:-}" node -e '
        const out = { sessionCookie: process.env.UITEST_COOKIE }
        if (process.env.UITEST_FIXTURES && process.env.UITEST_FIXTURES !== "null") out.fixtures = process.env.UITEST_FIXTURES
        if (process.env.UITEST_RUN) out.runId = process.env.UITEST_RUN
        if (process.env.UITEST_BASE_URL) out.baseURL = process.env.UITEST_BASE_URL
        process.stdout.write(JSON.stringify(out))' > "$json_tmp"
    plutil -convert xml1 -o "$SESSION_PLIST" "$json_tmp"
    rm -f "$json_tmp"

    if [[ -n "$UITEST_RUN_ID" ]]; then
        echo -e "${GREEN}✓ Test account for run ${UITEST_RUN_ID} written (cookie ${#cookie} chars, fixture ids included)${NC}"
    else
        echo -e "${GREEN}✓ Test-account session written (${#cookie} chars; shared account, no fixture ids)${NC}"
    fi
}

# Never leave a live credential lying in the working tree, nor a run's account on the server.
cleanup_uitest_session() {
    rm -f "$SESSION_PLIST"
    if [[ -n "$UITEST_RUN_ID" ]]; then
        uitest_account --delete-run "$UITEST_RUN_ID" >/dev/null 2>&1 \
            || echo -e "${YELLOW}⚠ Could not delete test account for run ${UITEST_RUN_ID}; the next mint reaps it after 24h${NC}"
    fi
}
