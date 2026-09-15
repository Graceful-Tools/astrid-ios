#!/bin/bash
#
# check-app-version-table.sh — keep astrid-web's RELEASED_APP_VERSIONS iOS row honest about what
# is actually on the App Store (Task AITD-407).
#
#   ./scripts/check-app-version-table.sh
#
# WHAT IT COMPARES. astrid-web hand-maintains the iOS row of `RELEASED_APP_VERSIONS` in
# `lib/app-version.ts`, served as `GET /api/v1/app-version?platform=ios`, and the client shows the
# in-app Update card when the running app is behind `latestVersion`. Nothing keeps that row in
# step with the store, and the event that makes it stale — a release going live — happens in THIS
# repo. So the axis is TABLE ↔ STORE.
#
# MARKETING_VERSION is deliberately not part of it: it is supposed to run ahead of the store for
# the whole stretch between a bump and a release (and this repo bumps it precisely to escape a
# released version — AITD-396), so comparing against it would fail on every ordinary day.
#
# iOS ONLY, AND THAT IS NOT AN OVERSIGHT. The Mac row is `{}` and is resolved per request from
# the GitHub Releases feed (`lib/mac-release.ts`), because the Mac app is not on the Mac App
# Store at all — it ships as a notarized DMG. Asking App Store Connect about Mac would compare
# against a record users cannot install from; hardcoding a number from it is exactly the bug
# AWTD-942 fixed, which shipped a card pointing Mac users at the iOS listing. Nothing here is
# hand-maintained for Mac, so there is nothing here to drift.
#
# THE TWO DIRECTIONS ARE NOT EQUALLY BAD, so they do not get the same exit code:
#
#   - TABLE AHEAD of the store — the row names a version nobody can install, so every user is
#     nagged on every launch to get a build that does not exist. It looks like a bug in the app.
#     That is a live user-facing defect: EXIT 1.
#   - TABLE BEHIND the store — users on the old build are simply never told an update exists.
#     Silent and mild, and it is also the correct state for the hours between a release going
#     live and someone updating the row. Warn and EXIT 0; failing here would make the check fire
#     during every successful release, which is how a gate comes to be ignored.
#
# ONLY READY_FOR_SALE COUNTS AS LIVE. REMOVED_FROM_SALE and REPLACED_WITH_NEW_INFO are "released"
# as far as check-version.sh is concerned (Apple has closed them to new builds) but they are not
# installable, so they are not something to point the Update card at.
#
# IT READS THE REPO, NOT THE ENDPOINT. `/api/v1/app-version` requires authentication (401 to an
# anonymous caller), and the file is the source the endpoint serves anyway. Reading it also
# catches an ahead-of-store row BEFORE it deploys, which is better than detecting it after.
#
# FAILS ONLY ON A POSITIVE AHEAD-OF-STORE FINDING. Like check-version.sh: no .env.local, no key,
# no network, no sibling astrid-web checkout, an answer it cannot parse → one "skipped" line and
# exit 0. A gate that cannot run on a plane is a worse bug than the one it prevents.
set -u
cd "$(dirname "$0")/.."

ENV_FILE="${CHECK_VERSION_ENV_FILE:-.env.local}"
TABLE_FILE="${APP_VERSION_TABLE_FILE:-../astrid-web/lib/app-version.ts}"

[ $# -eq 0 ] || { echo "Usage: ./scripts/check-app-version-table.sh    (iOS only — see the header)" >&2; exit 2; }

skip() { echo "⊘ App version table check skipped — $1"; exit 0; }

# --- Can this run at all? ---------------------------------------------------------
[ -f "$TABLE_FILE" ] || skip "no astrid-web checkout at $TABLE_FILE, so there is no table to check"
[ -f "$ENV_FILE" ] || skip "no $ENV_FILE here, so no App Store Connect key (cp ../astrid-web/.env.local .env.local to enable it)"
for n in APPLE_ASC_KEY_ID APPLE_ASC_ISSUER_ID APPLE_ASC_PRIVATE_KEY APPLE_APP_STORE_APP_ID; do
  grep -qE "^$n=." "$ENV_FILE" || skip "$n is not set in $ENV_FILE"
done

# The iOS row's latestVersion. Anchored on `ios:` so the Mac row — deliberately empty — can never
# be read by mistake, and tolerant of either quote style.
table=$(sed -n "s/^[[:space:]]*ios:[[:space:]]*{[^}]*latestVersion:[[:space:]]*['\"]\([^'\"]*\)['\"].*/\1/p" "$TABLE_FILE" | head -n 1)
if [ -z "$table" ]; then
  # An empty row is a real, documented state ("no update known" — the card simply does not show),
  # not a parse failure to panic about. Either way there is no claim to contradict.
  skip "no iOS latestVersion in $TABLE_FILE (an empty row is the safe 'no update known' state)"
fi
[[ "$table" =~ ^[0-9]+(\.[0-9]+)*$ ]] || skip "unexpected iOS version in the table: $table"

ERR=$(mktemp); live=$(ASC_ENV_FILE="$ENV_FILE" node scripts/asc-appstore.mjs released ios 2>"$ERR"); rc=$?
reason=$(head -n 1 "$ERR"); rm -f "$ERR"
[ "$rc" = 0 ] || skip "could not reach App Store Connect (${reason:-no detail})"
[ "$live" != "NONE" ] || skip "App Store Connect reports nothing released for iOS yet"
[[ "$live" =~ ^[0-9]+(\.[0-9]+)*$ ]] || skip "unexpected answer from App Store Connect: ${live:-empty}"

if [ "$table" = "$live" ]; then
  echo "✓ ios $table — the table matches the App Store"
  exit 0
fi

# Which way did it drift? `sort -V` orders version numbers properly (1.9.10 after 1.9.9).
newest=$(printf '%s\n%s\n' "$table" "$live" | sort -V | tail -n 1)
if [ "$newest" = "$table" ]; then
  echo "✗ ios: the table says $table but the App Store has $live — the table is AHEAD of the store."
  echo "  Every iOS user is being nagged on every launch to install $table, which they cannot get."
  echo "  Fix: set the ios latestVersion back to $live in astrid-web lib/app-version.ts"
  echo "  (RELEASED_APP_VERSIONS), and only raise it once the new version reads READY_FOR_SALE."
  exit 1
fi

echo "⚠ ios: the App Store has $live but the table still says $table — the table is BEHIND."
echo "  iOS users on $table are never told $live exists. Not a build blocker, and this is the"
echo "  expected state for a few hours after a release goes live."
echo "  Fix: set the ios latestVersion to $live in astrid-web lib/app-version.ts (RELEASED_APP_VERSIONS)."
exit 0
