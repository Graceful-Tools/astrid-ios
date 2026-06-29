#!/bin/sh

# Xcode Cloud custom build step: run the unit test suite on Apple's infrastructure
# so tests gate every build, independent of any local simulator.
#
# Why this script instead of a workflow TEST action: the "iOS Internal testers"
# workflow's TestFlight deployment is bound to its ARCHIVE action, and editing the
# workflow's actions via the API breaks that binding. A ci_scripts/ build step
# runs for every Xcode Cloud build without touching the workflow, and a non-zero
# exit here fails the build — so a red test blocks the TestFlight upload.
#
# Runs after the archive action. Unit tests only (Astrid AppTests); UI tests need
# a signed-in account and are intentionally excluded.

set -eu

echo "── ci_post_xcodebuild: running unit tests ──"

# Xcode Cloud checks out the repo at CI_PRIMARY_REPOSITORY_PATH.
cd "${CI_PRIMARY_REPOSITORY_PATH:-$(dirname "$0")/..}"

# Pick an available iPhone simulator so we don't pin a device that the image
# might rename across Xcode updates.
DEVICE="$(xcrun simctl list devices available 2>/dev/null \
  | grep -oE 'iPhone [0-9]+( Pro( Max)?)?' \
  | sort -t' ' -k2 -n \
  | tail -1)"
if [ -z "${DEVICE}" ]; then
  DEVICE="iPhone 16"
fi
echo "Using simulator: ${DEVICE}"

xcodebuild test \
  -scheme "Astrid App" \
  -destination "platform=iOS Simulator,name=${DEVICE}" \
  -only-testing:"Astrid AppTests" \
  -skipPackagePluginValidation \
  -resultBundlePath "${CI_RESULT_BUNDLE_PATH:-$PWD/UnitTests.xcresult}"

echo "── ci_post_xcodebuild: unit tests passed ──"
