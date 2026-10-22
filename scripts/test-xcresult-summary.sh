#!/bin/bash
#
# test-xcresult-summary.sh — the regression test for scripts/xcresult-summary.sh (Task AITD-524).
#
# run-tests.sh used to report "N passed, M skipped" by counting LOG LINES containing those words
# (`grep -c passed`), which is a line count, not a test count. And the UI job's failure reached
# nobody: 23 red runs on main in a row before an audit noticed. Both now read the result bundle,
# so this pins what the helper makes of xcresulttool's summary — with a fake `xcrun` first on
# PATH, so nothing here needs a real bundle or Xcode.
set -u
cd "$(dirname "$0")/.."

SUMMARY="$PWD/scripts/xcresult-summary.sh"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin" "$TMP/a.xcresult" "$TMP/b.xcresult"

# The fake xcrun: `xcresulttool get test-results summary --path <bundle>` answers per bundle.
cat > "$TMP/bin/xcrun" <<'STUB'
#!/bin/bash
[ "$1 $2 $3 $4" = "xcresulttool get test-results summary" ] || { echo "stub: unexpected $*" >&2; exit 1; }
case "$6" in
  */a.xcresult) cat <<'JSON'
{ "passedTests": 40, "skippedTests": 3, "failedTests": 0, "testFailures": [] }
JSON
  ;;
  */b.xcresult) cat <<'JSON'
{ "passedTests": 1, "skippedTests": 0, "failedTests": 1,
  "testFailures": [ { "testIdentifierString": "MonkeyUITests/testMonkeyStressesTheAppWithoutCrashingOrHanging()",
                      "targetName": "Astrid AppUITests",
                      "failureText": "Action 150 (tapRandomButton) took 60.6s, over the 10s hang threshold.\nReplay: MONKEY_SEED=20260826" } ] }
JSON
  ;;
  *) echo "not a result bundle" >&2; exit 1 ;;
esac
STUB
chmod +x "$TMP/bin/xcrun"

fail=0
expect() {  # expect <label> <wanted> <got>
  if [ "$2" = "$3" ]; then echo "✓ $1"; else echo "✗ $1"; echo "    want: $2"; echo "    got:  $3"; fail=1; fi
}

run() { PATH="$TMP/bin:$PATH" "$SUMMARY" "$@" 2>&1; }

expect "counts one bundle" "40 passed, 3 skipped, 0 failed" "$(run counts "$TMP/a.xcresult")"
expect "counts add across bundles" "41 passed, 3 skipped, 1 failed" "$(run counts "$TMP/a.xcresult" "$TMP/b.xcresult")"
expect "a bundle that does not exist is skipped, not fatal" "40 passed, 3 skipped, 0 failed" \
  "$(run counts "$TMP/a.xcresult" "$TMP/missing.xcresult")"
expect "failures name the test and the first line of why" \
  "MonkeyUITests/testMonkeyStressesTheAppWithoutCrashingOrHanging() — Action 150 (tapRandomButton) took 60.6s, over the 10s hang threshold." \
  "$(run failures "$TMP/a.xcresult" "$TMP/b.xcresult")"
expect "no failures prints nothing" "" "$(run failures "$TMP/a.xcresult")"

[ "$fail" -eq 0 ] || exit 1
echo "xcresult-summary: all checks passed"
