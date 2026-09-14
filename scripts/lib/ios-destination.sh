#!/bin/bash
# The one place the iOS simulator destination is spelled. Sourced by predeploy.sh, run-tests.sh,
# check-brands.sh and build-ios.sh.
#
# Extracted because the same "iPhone 17" literal was written in six scripts (2026-09-13 dedupe
# review), and a simulator rename meant editing all of them. Override the device with
# ASTRID_SIMULATOR_NAME (the same variable prepare-ios-simulator.sh reads), or the whole
# destination with ASTRID_IOS_DESTINATION — CI sets the latter to a booted UDID.

: "${ASTRID_SIMULATOR_NAME:=iPhone 17}"
: "${ASTRID_IOS_DESTINATION:=platform=iOS Simulator,name=${ASTRID_SIMULATOR_NAME}}"
export ASTRID_SIMULATOR_NAME ASTRID_IOS_DESTINATION
