#!/bin/bash

set -euo pipefail

DERIVED_DATA_PATH="/tmp/astrid-mac-dd"
COMMON_ARGS=(
    -scheme "Astrid Mac"
    -destination "platform=macOS,arch=arm64"
    -derivedDataPath "${DERIVED_DATA_PATH}"
    -quiet
)

SIGNING_ARGS=()
TEST_ARGS=()
if [[ "${CI:-}" == "true" ]]; then
    SIGNING_ARGS+=(
        CODE_SIGN_IDENTITY=-
        CODE_SIGNING_ALLOWED=YES
        CODE_SIGN_ENTITLEMENTS=
        ENABLE_APP_SANDBOX=NO
        ENABLE_HARDENED_RUNTIME=NO
    )
    # The local runner must be unsandboxed so source-contract tests can read the
    # checkout. This assertion specifically requires a sandboxed signature and
    # remains covered by the Xcode Cloud Mac lane.
    TEST_ARGS+=(
        -skip-testing:"Astrid MacTests/MacSignInOptionsTests/testItCanReadThisBuildsSignature"
    )
else
    SIGNING_ARGS+=(-allowProvisioningUpdates)
fi

xcodebuild build-for-testing "${COMMON_ARGS[@]}" "${SIGNING_ARGS[@]}"
xcodebuild test-without-building \
    "${COMMON_ARGS[@]}" \
    -only-testing:"Astrid MacTests" \
    -parallel-testing-enabled NO \
    "${TEST_ARGS[@]}" \
    "${SIGNING_ARGS[@]}"
