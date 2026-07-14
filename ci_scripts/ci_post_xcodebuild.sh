#!/bin/sh

# Xcode Cloud custom build step: run the unit suite on Apple's infra so tests
# gate the build, independent of any local simulator.
#
# Why a ci_scripts/ step instead of a workflow TEST action: the workflow's
# TestFlight deployment is bound to its ARCHIVE action, and editing the actions
# via the API breaks that binding. This script runs for every build without
# touching the workflow.
#
# Safety: this script only fails the build on a GENUINE test/build failure
# (xcodebuild exit 65). Infrastructure/usage errors (e.g. a missing simulator)
# are surfaced as warnings and DO NOT block the build — a bug in this script must
# never be able to break the TestFlight pipeline.

set -u
echo "── ci_post_xcodebuild: unit tests ──"

cd "${CI_PRIMARY_REPOSITORY_PATH:-$(dirname "$0")/..}" || exit 0

# First available iPhone simulator on the runner image (fallback: iPhone 16).
DEVICE="$(xcrun simctl list devices available 2>/dev/null | grep -oE 'iPhone 1[0-9]' | head -1)"
[ -z "${DEVICE}" ] && DEVICE="iPhone 16"
echo "Simulator: ${DEVICE}"

# Skip repo-introspection tests: they read source files via #filePath and the
# sibling astrid-web repo, which don't exist in Xcode Cloud's sandbox (only the
# astrid-ios repo is checked out). They run locally; here they'd false-fail.
xcodebuild test \
  -scheme "Astrid App" \
  -destination "platform=iOS Simulator,name=${DEVICE}" \
  -only-testing:"Astrid AppTests" \
  -skip-testing:"Astrid AppTests/V1APIContractIntegrationTests" \
  -skip-testing:"Astrid AppTests/CanonicalControlPointsTests/testRefactoredViews_DoNotCallAstridAPIClientDirectly"
RC=$?
echo "xcodebuild test exit code: ${RC}"

# macOS lane: build + unit-test the Astrid Mac target on the same runner.
# macOS builds on the host (no simulator). Same safety rule: only a genuine
# test failure (exit 65) blocks the build.
echo "── ci_post_xcodebuild: macOS build + tests (Astrid Mac) ──"
xcodebuild test \
  -scheme "Astrid Mac" \
  -destination "platform=macOS" \
  -only-testing:"Astrid MacTests" \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_ALLOWED=YES
RC_MAC=$?
echo "macOS test exit code: ${RC_MAC}"
if [ "${RC_MAC}" -eq 65 ]; then
  echo "── macOS tests FAILED — blocking the build ──"
  exit 1
fi

if [ "${RC}" -eq 0 ]; then
  echo "── unit tests passed ──"
  exit 0
fi
if [ "${RC}" -eq 65 ]; then
  echo "── unit tests FAILED — blocking the build ──"
  exit 1
fi
echo "── WARN: xcodebuild exited ${RC} (infra/usage, not a test failure) — not blocking ──"
exit 0
