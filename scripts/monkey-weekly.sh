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
# To schedule it, render and install the launchd job — the installer fills in this
# checkout's path, so there is nothing to edit by hand:
#   ./scripts/launchd/install.sh cc.astrid.monkey.weekly
#
# The digest lands in build/monkey/weekly-<date>.md and the last line is RESULT:, so a scheduler
# (or a person skimming) can tell what happened without reading the logs.
#
# The result goes to the board, not just a file (AITD-530): the RESULT line and each platform's
# "after dropping noise" block are posted to the iOS list's Astrid chat, the same channel /fixall
# reports to, and a platform that did not survive files an Astrid task (one per platform; a
# repeat while it is still open is refused by the filer). A HARNESS result — locked screen —
# posts but files nothing: it is a fact about the machine, not the app. For four weeks the
# digests landed in build/monkey/ and nobody read them. ASTRID_MONKEY_NO_POST=1 keeps a run local.
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

WEB="$ROOT/../astrid-web"
IOS_LIST_ID="aa41c1a3-bd63-4c6d-9b87-42c6e0aafa36"
POST=""          # the board message, built per platform below

# Lines a person should read: the "after dropping noise" block plus the yes/no counts.
findings_excerpt() {
  sed -n '/after dropping known test-environment noise:/,$p' "$1" 2>/dev/null | head -20 | cut -c1-200
}

OVERALL="ok"
for target in ios mac; do
  echo "=== $target ==="
  set +e
  ./scripts/monkey-test.sh "$target" --actions "$ACTIONS" --seed "$SEED" 2>&1 | tail -40
  rc=${PIPESTATUS[0]}
  set -e
  case "$rc" in
    0) status="Survived $ACTIONS random actions." ;;
    3) status="**HARNESS** — could not run (locked screen?); says nothing about the app."
       [ "$OVERALL" = "failed" ] || OVERALL="harness" ;;
    *) status="**FAILED** — see \`build/monkey/monkey-$target.log\`."
       OVERALL="failed" ;;
  esac

  # A HARNESS exit stops before the sweep, so its findings file is last week's: leave it out.
  excerpt=""
  [ "$rc" -eq 3 ] || excerpt=$(findings_excerpt "$ROOT/build/monkey/findings-$target.txt")
  POST+="## $target"$'\n'"$status"$'\n'
  [ -z "$excerpt" ] || POST+=$'```\n'"$excerpt"$'\n```\n'

  if [ "$rc" -ne 0 ] && [ "$rc" -ne 3 ] && [ -z "${ASTRID_MONKEY_NO_POST:-}" ] && [ -d "$WEB" ]; then
    (cd "$WEB" && npx tsx scripts/file-ios-task.ts \
      "Weekly monkey: the $target app did not survive the random run" \
      "The weekly monkey ($WEEK, seed $SEED, $ACTIONS actions) reported FAILED on $target. Replay: \`./scripts/monkey-test.sh $target --actions $ACTIONS --seed $SEED\`. Log: \`build/monkey/monkey-$target.log\` on the Mac that ran it."$'\n\n```\n'"$excerpt"$'\n```' \
      -p 2) || echo "  (could not file the task — see above)"
  fi

  {
    echo "## $target"
    echo ""
    echo "$status"
    echo ""
    echo '```'
    if [ "$rc" -eq 3 ]; then echo "(not run)"; else cat "$ROOT/build/monkey/findings-$target.txt" 2>/dev/null || echo "(no findings file)"; fi
    echo '```'
    echo ""
  } >> "$DIGEST"
done

echo ""
echo "Digest: $DIGEST"
case "$OVERALL" in
  ok)      RESULT="RESULT: OK — both platforms survived. Read $DIGEST for what the apps logged." ;;
  harness) RESULT="RESULT: HARNESS — a platform could not run (locked screen?); the rest survived. Read $DIGEST." ;;
  *)       RESULT="RESULT: FAILED — at least one platform did not survive. Read $DIGEST." ;;
esac

if [ -z "${ASTRID_MONKEY_NO_POST:-}" ] && [ -d "$WEB" ]; then
  (cd "$WEB" && npx tsx scripts/post-list-message.ts "$IOS_LIST_ID" \
    "# Weekly monkey — $WEEK"$'\n'"${RESULT%% Read *}"$'\n\n'"Seed \`$SEED\`, $ACTIONS actions per platform."$'\n\n'"$POST") \
    || echo "  (could not post to the board — see above)"
fi

echo "$RESULT"
