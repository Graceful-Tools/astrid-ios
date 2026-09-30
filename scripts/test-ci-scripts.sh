#!/bin/bash
#
# test-ci-scripts.sh — pins the one thing in ci_scripts/ that silently stopped every Mac build.
#
# ci_post_xcodebuild.sh overrides CODE_SIGN_ENTITLEMENTS on the xcodebuild command line, and a
# command-line build setting applies to EVERY target in the build, the AstridCore Swift package's
# included. Given as a relative path, each target resolves it from its own project's folder:
# Packages/AstridCore/ci_scripts/… does not exist, the package target fails with "Build input
# file cannot be found", the Mac unit lane exits 65, and the script blocks the build. Every Mac
# TestFlight build from the astrid-core move (runs 1078, 1081, 1083) died there while the local
# gates, which never run this script, stayed green.
#
# So an entitlements path passed from ci_scripts/ must be absolute.
set -u
cd "$(dirname "$0")/.."

fail=0
while IFS= read -r line; do
  value="${line#*CODE_SIGN_ENTITLEMENTS=}"
  value="${value#\"}"
  case "$value" in
    /*|\$PWD/*|\$\{PWD\}/*|\$REPO/*|\$\{REPO\}/*|\$CI_PRIMARY_REPOSITORY_PATH/*|\$\{CI_PRIMARY_REPOSITORY_PATH\}/*) ;;
    *) echo "✗ relative CODE_SIGN_ENTITLEMENTS in ci_scripts: $line"; fail=1 ;;
  esac
done < <(grep -h 'CODE_SIGN_ENTITLEMENTS=' ci_scripts/*.sh)

if [ "$fail" -ne 0 ]; then
  echo "  A command-line setting reaches the AstridCore package target too; make the path absolute."
  exit 1
fi
echo "✓ ci-scripts: entitlements paths are absolute"
