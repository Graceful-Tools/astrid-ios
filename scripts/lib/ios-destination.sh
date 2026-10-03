#!/bin/bash
# The one place the iOS simulator destination is spelled. Sourced by predeploy.sh, run-tests.sh,
# check-brands.sh and build-ios.sh.
#
# Extracted because the same "iPhone 17" literal was written in six scripts (2026-09-13 dedupe
# review), and a simulator rename meant editing all of them. Override the device with
# ASTRID_SIMULATOR_NAME (the same variable prepare-ios-simulator.sh reads), or the whole
# destination with ASTRID_IOS_DESTINATION — CI sets the latter to a booted UDID.
#
# OS=latest because a bare name matches one simulator per installed runtime and xcodebuild takes
# the first. On 2026-10-03 that was iOS 26.2, whose concurrency runtime aborts in main-actor
# deinits (AITD-457; fixed by 26.5), so the suite crashed there and passed everywhere else.

: "${ASTRID_SIMULATOR_NAME:=iPhone 17}"
: "${ASTRID_IOS_DESTINATION:=platform=iOS Simulator,name=${ASTRID_SIMULATOR_NAME},OS=latest}"
export ASTRID_SIMULATOR_NAME ASTRID_IOS_DESTINATION
