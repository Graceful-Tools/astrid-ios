#!/bin/bash
#
# test-check-version.sh — the regression test for scripts/check-version.sh (Task AITD-396).
#
# The check talks to App Store Connect through `node scripts/asc-appstore.mjs`, so this puts a
# fake `node` first on PATH and scripts each answer it should handle. Nothing here touches the
# network or a real key: the env file is a temp file holding placeholder names.
#
# What is pinned:
#   - a released version (READY_FOR_SALE / REMOVED_FROM_SALE / REPLACED_WITH_NEW_INFO) FAILS,
#     and the message names the target, the pbxproj file and the rule that a human picks the
#     new number;
#   - an unreleased or unknown version passes;
#   - no key, or an App Store Connect the script cannot reach, SKIPS and passes — a predeploy
#     that cannot run on a plane is a worse bug than the one this prevents;
#   - `all` checks BOTH targets, and one released version is enough to fail the run.
set -u
cd "$(dirname "$0")/.."

CHECK="$PWD/scripts/check-version.sh"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin"
ENV_FILE="$TMP/env.local"
printf 'APPLE_ASC_KEY_ID=k\nAPPLE_ASC_ISSUER_ID=i\nAPPLE_ASC_PRIVATE_KEY="p"\nAPPLE_APP_STORE_APP_ID=1\n' > "$ENV_FILE"

# The fake node: `version-state <target> <version>` answers from a table, everything else dies.
cat > "$TMP/bin/node" <<'STUB'
#!/bin/bash
[ "${2:-}" = "version-state" ] || { echo "stub: unexpected $*" >&2; exit 1; }
[ -z "${STUB_FAIL:-}" ] || { echo "$STUB_FAIL" >&2; exit 1; }
case "$3:$4" in
  ios:1.9.2) echo READY_FOR_SALE ;;
  ios:1.9.3) echo NOT_FOUND ;;
  ios:1.9.4) echo PREPARE_FOR_SUBMISSION ;;
  ios:1.8.0) echo REMOVED_FROM_SALE ;;
  ios:1.7.0) echo REPLACED_WITH_NEW_INFO ;;
  mac:1.1.1) echo READY_FOR_SALE ;;
  mac:1.1.2) echo NOT_FOUND ;;
  *) echo NOT_FOUND ;;
esac
STUB
chmod +x "$TMP/bin/node"

PASS=0; FAIL=0
run() {  # run <expected-exit> <description> -- <args…>   (stdout+stderr captured in $OUT)
  local want="$1" desc="$2"; shift 3
  OUT=$(PATH="$TMP/bin:$PATH" CHECK_VERSION_ENV_FILE="$ENV_FILE" "$CHECK" "$@" 2>&1); local got=$?
  if [ "$got" = "$want" ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "✗ $desc — exit $got, wanted $want"; echo "$OUT" | sed 's/^/    /'; fi
}
expect_out() {  # expect_out <description> <grep pattern>   (case-insensitive, against the last $OUT)
  if grep -qi -- "$2" <<<"$OUT"; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "✗ $1 — output lacks '$2':"; echo "$OUT" | sed 's/^/    /'; fi
}

[ -x "$CHECK" ] || { echo "✗ $CHECK is missing or not executable"; exit 1; }

# --- A released version is a hard stop ---------------------------------------------
run 1 "iOS at a READY_FOR_SALE version fails" -- ios --version 1.9.2
expect_out "…names the target"                "ios"
expect_out "…names the state"                 "READY_FOR_SALE"
expect_out "…points at the pbxproj"           "Astrid App.xcodeproj/project.pbxproj"
expect_out "…says MARKETING_VERSION"          "MARKETING_VERSION"
expect_out "…says a human picks the number"   "ask the user"
run 1 "REMOVED_FROM_SALE is released too"      -- ios --version 1.8.0
run 1 "REPLACED_WITH_NEW_INFO is released too" -- ios --version 1.7.0
run 1 "Mac at a READY_FOR_SALE version fails"  -- mac --version 1.1.1
expect_out "…names the Mac target"            "mac"

# --- Anything else passes -----------------------------------------------------------
run 0 "a version App Store Connect has never seen passes" -- ios --version 1.9.3
run 0 "a version still being prepared passes"             -- ios --version 1.9.4
run 0 "Mac at an unreleased version passes"               -- mac --version 1.1.2

# --- Both targets at once ------------------------------------------------------------
run 1 "all: one released target fails the run"  -- all --version-ios 1.9.3 --version-mac 1.1.1
expect_out "…and says which one"                "mac"
run 0 "all: both unreleased passes"             -- all --version-ios 1.9.3 --version-mac 1.1.2

# --- Offline and keyless runs skip, they do not fail ---------------------------------
OUT=$(PATH="$TMP/bin:$PATH" CHECK_VERSION_ENV_FILE="$TMP/missing.local" "$CHECK" ios --version 1.9.2 2>&1); got=$?
if [ "$got" = 0 ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "✗ no env file should skip — exit $got"; echo "$OUT"; fi
expect_out "no env file says it skipped" "skipped"

printf 'APPLE_ASC_KEY_ID=k\n' > "$TMP/partial.local"
OUT=$(PATH="$TMP/bin:$PATH" CHECK_VERSION_ENV_FILE="$TMP/partial.local" "$CHECK" ios --version 1.9.2 2>&1); got=$?
if [ "$got" = 0 ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "✗ partial key should skip — exit $got"; echo "$OUT"; fi
expect_out "partial key says it skipped" "skipped"

OUT=$(PATH="$TMP/bin:$PATH" CHECK_VERSION_ENV_FILE="$ENV_FILE" STUB_FAIL="fetch failed: ENOTFOUND api.appstoreconnect.apple.com" "$CHECK" ios --version 1.9.2 2>&1); got=$?
if [ "$got" = 0 ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "✗ unreachable ASC should skip — exit $got"; echo "$OUT"; fi
expect_out "unreachable ASC says it skipped"     "skipped"
expect_out "…and carries the reason"             "ENOTFOUND"

# --- Bad arguments are loud ----------------------------------------------------------
run 2 "an unknown target is rejected" -- watch --version 1.0

echo ""
if [ "$FAIL" = 0 ]; then echo "✓ check-version: $PASS checks passed"; exit 0; fi
echo "✗ check-version: $FAIL failed, $PASS passed"; exit 1
