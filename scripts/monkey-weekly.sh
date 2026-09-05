#!/bin/bash
#
# monkey-weekly.sh — the unattended weekly run: both platforms, then a digest.
#
# Kept separate from monkey-test.sh so the interactive script stays a single-purpose thing you
# can point at one platform. This one is what a scheduler calls.
#
#   ./scripts/monkey-weekly.sh                 # both platforms, 200 actions each
#   ./scripts/monkey-weekly.sh --actions 500
#
# The digest lands in build/monkey/weekly-<date>.md and the last line is RESULT:, so a scheduler
# (or a person skimming) can tell what happened without reading the logs.
#
# The seed varies by week ON PURPOSE. A fixed seed would walk the same path every time and stop
# finding anything new after the first run; the week number is written into the digest so any
# run can be replayed exactly with `--seed`.
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$PWD"
ACTIONS=200
while [ $# -gt 0 ]; do
  case "$1" in
    --actions) ACTIONS="${2:-200}"; shift ;;
    *) echo "RESULT: FAILED — unknown option \"$1\""; exit 2 ;;
  esac
  shift
done

WEEK=$(date +%Y-W%V)
SEED=$(date +%Y%V)          # same every day within a week, different next week
DIGEST="$ROOT/build/monkey/weekly-$WEEK.md"
mkdir -p "$ROOT/build/monkey"

{
  echo "# Monkey run — $WEEK"
  echo ""
  echo "Seed \`$SEED\`, $ACTIONS actions per platform. Replay any of this with:"
  echo '```'
  echo "./scripts/monkey-test.sh <ios|mac> --actions $ACTIONS --seed $SEED"
  echo '```'
  echo ""
} > "$DIGEST"

OVERALL="ok"
for target in ios mac; do
  echo "=== $target ==="
  if [ "$target" = "mac" ]; then
    LAST_SUCCESS_FILE="$ROOT/build/monkey/last-success-mac.txt"
  else
    LAST_SUCCESS_FILE="$ROOT/build/monkey/last-success-ios.txt"
  fi
  set +e
  ./scripts/monkey-test.sh "$target" --actions "$ACTIONS" --seed "$SEED" 2>&1 | tail -40
  rc=${PIPESTATUS[0]}
  set -e
  STATUS_NOTE=""
  if [ "$rc" -eq 0 ]; then
    date -u +"%Y-%m-%dT%H:%M:%SZ" > "$LAST_SUCCESS_FILE"
  else
    OVERALL="failed"
    if [ "$target" = "mac" ]; then
      if [ -s "$LAST_SUCCESS_FILE" ]; then
        STATUS_NOTE="Mac monkey has not run successfully since $(cat "$LAST_SUCCESS_FILE")."
      else
        STATUS_NOTE="Mac monkey has not run successfully since this schedule was installed (no successful run recorded)."
      fi
      echo "WARNING: $STATUS_NOTE"
      osascript -e "display notification \"$STATUS_NOTE\" with title \"Astrid weekly monkey\"" \
        >/dev/null 2>&1 || true
    fi
  fi

  {
    echo "## $target"
    echo ""
    if [ "$rc" -eq 0 ]; then echo "Survived $ACTIONS random actions."; else echo "**FAILED** — see \`build/monkey/monkey-$target.log\`."; fi
    [ -z "$STATUS_NOTE" ] || echo "**$STATUS_NOTE**"
    echo ""
    echo '```'
    cat "$ROOT/build/monkey/findings-$target.txt" 2>/dev/null || echo "(no findings file)"
    echo '```'
    echo ""
  } >> "$DIGEST"
done

echo ""
echo "Digest: $DIGEST"
if [ "$OVERALL" = "ok" ]; then
  echo "RESULT: OK — both platforms survived. Read $DIGEST for what the apps logged."
else
  echo "RESULT: FAILED — at least one platform did not survive. Read $DIGEST."
fi
