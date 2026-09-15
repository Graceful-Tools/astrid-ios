#!/bin/bash
#
# test-check-app-version-table.sh — regression test for scripts/check-app-version-table.sh
# (Task AITD-407).
#
# The check reads two sources, so both are faked: a temp copy of astrid-web's
# `lib/app-version.ts` (via APP_VERSION_TABLE_FILE) and `node scripts/asc-appstore.mjs released`
# (via a stub first on PATH). Nothing here touches the network or a real key.
#
# What is pinned:
#   - table AHEAD of the store FAILS, and says so in the words that matter (ahead, nagged, and
#     where to edit) — this is the loud, user-facing direction;
#   - table BEHIND the store WARNS and passes — it is the normal state right after a release,
#     and failing on it would make the check fire on every successful release;
#   - table matching the store passes quietly;
#   - versions compare numerically, so 1.9.10 is NEWER than 1.9.9 rather than sorting before it;
#   - the deliberately EMPTY Mac row is never mistaken for the iOS row — the bug that would make
#     this check compare against a platform that is not on the App Store at all (AWTD-942);
#   - no key, no astrid-web checkout, an unreachable App Store Connect, an empty iOS row, or
#     nothing released yet all SKIP and pass.
set -u
cd "$(dirname "$0")/.."

CHECK="$PWD/scripts/check-app-version-table.sh"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin"
ENV_FILE="$TMP/env.local"
printf 'APPLE_ASC_KEY_ID=k\nAPPLE_ASC_ISSUER_ID=i\nAPPLE_ASC_PRIVATE_KEY="p"\nAPPLE_APP_STORE_APP_ID=1\n' > "$ENV_FILE"
TABLE="$TMP/app-version.ts"

# Fake App Store Connect: `released ios` answers from LIVE_IOS.
cat > "$TMP/bin/node" <<'STUB'
#!/bin/bash
[ "${2:-}" = "released" ] || { echo "stub: unexpected $*" >&2; exit 1; }
[ -z "${STUB_ASC_FAIL:-}" ] || { echo "$STUB_ASC_FAIL" >&2; exit 1; }
echo "${LIVE_IOS:-1.9.2}"
STUB
chmod +x "$TMP/bin/node"

# Write a table file in the real file's shape: an iOS row, and a Mac row that is empty on purpose.
write_table() {  # write_table <ios-row-body>
  cat > "$TABLE" <<EOF
export const RELEASED_APP_VERSIONS: Readonly<Record<AppPlatform, AppVersionInfo>> = {
  ios: { $1 },
  /** EMPTY ON PURPOSE — Mac is resolved at request time from GitHub Releases. */
  mac: {},
}
EOF
}

PASS=0; FAIL=0
run() {  # run <expected-exit> <description>   (stdout+stderr captured in $OUT)
  local want="$1" desc="$2"
  OUT=$(PATH="$TMP/bin:$PATH" CHECK_VERSION_ENV_FILE="$ENV_FILE" APP_VERSION_TABLE_FILE="$TABLE" "$CHECK" 2>&1); local got=$?
  if [ "$got" = "$want" ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "✗ $desc — exit $got, wanted $want"; echo "$OUT" | sed 's/^/    /'; fi
}
expect_out() {  # expect_out <description> <grep pattern>   (case-insensitive, against the last $OUT)
  if grep -qi -- "$2" <<<"$OUT"; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "✗ $1 — output lacks '$2':"; echo "$OUT" | sed 's/^/    /'; fi
}
refute_out() {
  if grep -qi -- "$2" <<<"$OUT"; then FAIL=$((FAIL+1)); echo "✗ $1 — output should NOT contain '$2':"; echo "$OUT" | sed 's/^/    /'; else PASS=$((PASS+1)); fi
}

[ -x "$CHECK" ] || { echo "✗ $CHECK is missing or not executable"; exit 1; }

# --- Table AHEAD of the store is the loud failure ------------------------------------
write_table "latestVersion: '1.9.3', updateUrl: APP_STORE_URL"; export LIVE_IOS=1.9.2
run 1 "table ahead of the store fails"
expect_out "…names both versions"          "1.9.3"
expect_out "…says which way it drifted"    "ahead"
expect_out "…says users are being nagged"  "nagged"
expect_out "…points at the web table"      "lib/app-version.ts"
expect_out "…names the constant"           "RELEASED_APP_VERSIONS"

# --- Table BEHIND the store warns but passes -----------------------------------------
write_table "latestVersion: '1.9.1', updateUrl: APP_STORE_URL"; export LIVE_IOS=1.9.2
run 0 "table behind the store passes"
expect_out "…but still says so"         "behind"
expect_out "…and says where to fix it"  "lib/app-version.ts"

# --- In step is quiet ------------------------------------------------------------------
write_table "latestVersion: '1.9.2', updateUrl: APP_STORE_URL"; export LIVE_IOS=1.9.2
run 0 "a table matching the store passes"
expect_out "…and says it matches"        "matches"

# --- Double quotes parse too --------------------------------------------------------------
write_table 'latestVersion: "1.9.2", updateUrl: APP_STORE_URL'; export LIVE_IOS=1.9.2
run 0 "a double-quoted version parses"
expect_out "…and is read correctly"      "matches"

# --- Versions compare numerically, not as text ------------------------------------------
# "1.9.9" > "1.9.10" as strings, so a text compare would call this AHEAD and fail.
write_table "latestVersion: '1.9.9'"; export LIVE_IOS=1.9.10
run 0 "1.9.9 is BEHIND 1.9.10, not ahead of it"
expect_out "…and is reported as behind"  "behind"

write_table "latestVersion: '1.9.10'"; export LIVE_IOS=1.9.9
run 1 "1.9.10 is AHEAD of 1.9.9"

# --- The empty Mac row must never be read as the iOS row -------------------------------------
# The Mac app is not on the App Store (AWTD-942); reading `mac: {}` as the iOS row, or falling
# through to it, would compare against a platform this check has no business judging.
write_table "latestVersion: '1.9.2'"; export LIVE_IOS=1.9.2
run 0 "the empty mac row does not disturb a healthy iOS row"
refute_out "…and mac is never mentioned as a finding" "mac:"

cat > "$TABLE" <<'EOF'
export const RELEASED_APP_VERSIONS = {
  ios: {},
  mac: { latestVersion: '1.1.1' },
}
EOF
export LIVE_IOS=1.9.2
run 0 "an empty iOS row skips instead of reading the mac row"
expect_out "…and says it skipped"                 "skipped"
refute_out "…and never adopts the mac number"     "1.1.1"

# --- Nothing released yet is not a finding -------------------------------------------------
write_table "latestVersion: '1.9.2'"; export LIVE_IOS=NONE
run 0 "no released version yet skips"
expect_out "…and says it skipped"  "skipped"
unset LIVE_IOS

# --- Offline, keyless and checkout-less runs skip, they do not fail ----------------------------
write_table "latestVersion: '1.9.2'"
OUT=$(PATH="$TMP/bin:$PATH" CHECK_VERSION_ENV_FILE="$TMP/missing.local" APP_VERSION_TABLE_FILE="$TABLE" "$CHECK" 2>&1); got=$?
if [ "$got" = 0 ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "✗ no env file should skip — exit $got"; echo "$OUT"; fi
expect_out "no env file says it skipped" "skipped"

printf 'APPLE_ASC_KEY_ID=k\n' > "$TMP/partial.local"
OUT=$(PATH="$TMP/bin:$PATH" CHECK_VERSION_ENV_FILE="$TMP/partial.local" APP_VERSION_TABLE_FILE="$TABLE" "$CHECK" 2>&1); got=$?
if [ "$got" = 0 ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "✗ partial key should skip — exit $got"; echo "$OUT"; fi
expect_out "partial key says it skipped" "skipped"

OUT=$(PATH="$TMP/bin:$PATH" CHECK_VERSION_ENV_FILE="$ENV_FILE" APP_VERSION_TABLE_FILE="$TMP/no-such-repo.ts" "$CHECK" 2>&1); got=$?
if [ "$got" = 0 ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "✗ no astrid-web checkout should skip — exit $got"; echo "$OUT"; fi
expect_out "a missing astrid-web checkout says it skipped" "skipped"

OUT=$(PATH="$TMP/bin:$PATH" CHECK_VERSION_ENV_FILE="$ENV_FILE" APP_VERSION_TABLE_FILE="$TABLE" STUB_ASC_FAIL="fetch failed: ENOTFOUND api.appstoreconnect.apple.com" "$CHECK" 2>&1); got=$?
if [ "$got" = 0 ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "✗ unreachable ASC should skip — exit $got"; echo "$OUT"; fi
expect_out "unreachable ASC says it skipped" "skipped"
expect_out "…and carries the reason"         "ENOTFOUND"

# --- Bad arguments are loud ------------------------------------------------------------------
OUT=$(PATH="$TMP/bin:$PATH" CHECK_VERSION_ENV_FILE="$ENV_FILE" APP_VERSION_TABLE_FILE="$TABLE" "$CHECK" mac 2>&1); got=$?
if [ "$got" = 2 ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "✗ an argument should be rejected — exit $got"; echo "$OUT"; fi
expect_out "…and the usage explains it is iOS only" "iOS only"

echo ""
if [ "$FAIL" = 0 ]; then echo "✓ check-app-version-table: $PASS checks passed"; exit 0; fi
echo "✗ check-app-version-table: $FAIL failed, $PASS passed"; exit 1
