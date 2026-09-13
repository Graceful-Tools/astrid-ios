#!/bin/bash
#
# check-version.sh — stop before building on a MARKETING_VERSION the App Store has already
# released (Task AITD-396).
#
#   ./scripts/check-version.sh all                      # both targets, versions read from Xcode
#   ./scripts/check-version.sh ios                      # one target
#   ./scripts/check-version.sh mac --version 1.1.2      # a version the caller already knows
#   ./scripts/check-version.sh all --version-ios 1.9.3 --version-mac 1.1.2
#
# WHY. Once a version goes READY_FOR_SALE Apple closes its train and rejects every later upload
# under it, TestFlight included. Xcode Cloud reports that as a bare "PrepareBuildForAppStoreConnect
# failed" with every earlier action green — nine minutes and a diagnosis per occurrence, and it
# happened on the Mac (2026-09-12, 1.1.1) and on iOS (2026-09-13, 1.9.2, twice) within two days.
# `appstore-release.sh` has guarded the LOCAL upload path with this exact question since
# 2026-08-23; the cloud path — the one every push takes — had nothing. This is that check, shared.
#
# BOTH TARGETS, ALWAYS. iOS (1.9.x) and Mac (1.1.x) version independently under one App Store
# Connect record, and the failure is precisely that one of them drifts while the other is fine.
#
# FAILS ONLY ON A POSITIVE COLLISION. Predeploy is otherwise fully offline. No .env.local, no
# App Store Connect key, no network → one "skipped" line and exit 0. A gate that cannot run on a
# plane is a worse bug than the one this prevents. The only exit 1 is "App Store Connect says
# this version is released".
#
# State, not dates: `asc-appstore.mjs versions` prints createdDate, which is when the version
# record was made, not when it shipped. `appStoreState` needs no timing logic at all.
set -u
cd "$(dirname "$0")/.."

# The test harness points this at a temp file; real runs read .env.local like every sibling.
ENV_FILE="${CHECK_VERSION_ENV_FILE:-.env.local}"
PBXPROJ='Astrid App.xcodeproj/project.pbxproj'

usage() {
  echo "Usage: ./scripts/check-version.sh <ios|mac|all> [--version X | --version-ios X --version-mac X]" >&2
  exit 2
}

TARGET="${1:-}"; [ -n "$TARGET" ] && shift
VERSION_IOS=""; VERSION_MAC=""; VERSION_ONE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --version)     VERSION_ONE="${2:-}"; shift ;;
    --version-ios) VERSION_IOS="${2:-}"; shift ;;
    --version-mac) VERSION_MAC="${2:-}"; shift ;;
    *) usage ;;
  esac
  shift
done

case "$TARGET" in
  ios) TARGETS="ios"; VERSION_IOS="${VERSION_ONE:-$VERSION_IOS}" ;;
  mac) TARGETS="mac"; VERSION_MAC="${VERSION_ONE:-$VERSION_MAC}" ;;
  all) TARGETS="ios mac"; [ -z "$VERSION_ONE" ] || usage ;;
  *) usage ;;
esac

skip() { echo "⊘ App Store version check skipped — $1"; exit 0; }

# --- Can this run at all? ---------------------------------------------------------
[ -f "$ENV_FILE" ] || skip "no $ENV_FILE here, so no App Store Connect key (cp ../astrid-web/.env.local .env.local to enable it)"
for n in APPLE_ASC_KEY_ID APPLE_ASC_ISSUER_ID APPLE_ASC_PRIVATE_KEY APPLE_APP_STORE_APP_ID; do
  grep -qE "^$n=." "$ENV_FILE" || skip "$n is not set in $ENV_FILE"
done

# Read from the scheme's own build settings: grepping project.pbxproj returns whichever target
# comes first in the file (the iOS app), which silently mislabels the Mac.
marketing_version() {
  local scheme dest
  case "$1" in
    ios) scheme="Astrid App"; dest="generic/platform=iOS" ;;
    mac) scheme="Astrid Mac"; dest="generic/platform=macOS" ;;
  esac
  xcodebuild -scheme "$scheme" -destination "$dest" -showBuildSettings 2>/dev/null \
    | awk 'index($0, " MARKETING_VERSION = ") { sub(/.* = /, ""); print; exit }'
}

FAILED=0
for t in $TARGETS; do
  case "$t" in ios) v="$VERSION_IOS"; lines=4 ;; mac) v="$VERSION_MAC"; lines=2 ;; esac
  if [ -z "$v" ]; then
    v=$(marketing_version "$t")
    [ -n "$v" ] || skip "could not read MARKETING_VERSION for $t from xcodebuild"
  fi

  ERR=$(mktemp); state=$(ASC_ENV_FILE="$ENV_FILE" node scripts/asc-appstore.mjs version-state "$t" "$v" 2>"$ERR"); rc=$?
  reason=$(head -n 1 "$ERR"); rm -f "$ERR"
  [ "$rc" = 0 ] || skip "could not reach App Store Connect for $t $v (${reason:-no detail})"
  [[ "$state" =~ ^[A-Z_]+$ ]] || skip "unexpected answer from App Store Connect for $t $v: ${state:-empty}"

  case "$state" in
    READY_FOR_SALE|REMOVED_FROM_SALE|REPLACED_WITH_NEW_INFO)
      FAILED=1
      echo "✗ $t: MARKETING_VERSION $v is already released on the App Store ($state)."
      echo "  Apple closes a released version to new builds, so Xcode Cloud and TestFlight uploads under it"
      echo "  fail with a bare \"PrepareBuildForAppStoreConnect failed\" — after the whole run."
      echo "  Fix: raise MARKETING_VERSION for the $t target in \"$PBXPROJ\" ($lines lines),"
      echo "  then run this again. Ask the user which version number to use; do not pick one yourself."
      ;;
    *)
      echo "✓ $t $v — not released ($state)"
      ;;
  esac
done

exit $FAILED
