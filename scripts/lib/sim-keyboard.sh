#!/bin/bash
# Put an iOS simulator back on its on-screen keyboard before a UI run (ADEV-214).
#
# A UI test that sends a modifier key — E2EJourneyUITests' ⌘A — makes the simulator record a
# hardware keyboard: `HardwareKeyboardLastSeen` in the device's com.apple.keyboard.preferences.
# With `AutomaticMinimizationEnabled` (the default) the software keyboard then stays minimized
# in every LATER run on that device, across reboots, because the flag lives in the device's data.
# Every keyboard test after that is testing a keyboard nobody can see: CommentUITests' drag
# failed in CI that way while passing on a freshly used simulator.
#
# Clearing the flag only takes effect once the simulator restarts, so a set flag costs one
# reboot; a clear one costs a single `defaults read`.
#
# Sourced by prepare-ios-simulator.sh and run-tests.sh. `XCRUN` is overridable for the
# self-test (scripts/test-sim-keyboard.sh).

: "${XCRUN:=xcrun}"

# The UDID xcodebuild would pick for a destination string: an explicit `id=`, or the named
# device on the newest runtime (what `OS=latest` means). Empty when nothing matches.
sim_udid_for_destination() {
    local destination="$1"
    if [[ "$destination" =~ id=([0-9A-Fa-f-]+) ]]; then
        echo "${BASH_REMATCH[1]}"
        return 0
    fi
    local name="${ASTRID_SIMULATOR_NAME:-iPhone 17}"
    if [[ "$destination" =~ name=([^,]+) ]]; then
        name="${BASH_REMATCH[1]}"
    fi
    DEVICES_JSON="$("$XCRUN" simctl list devices available -j)" DEVICE_NAME="$name" node <<'NODE'
const devices = JSON.parse(process.env.DEVICES_JSON).devices
const match = Object.entries(devices)
  .flatMap(([runtime, entries]) =>
    entries.filter(d => d.isAvailable && d.name === process.env.DEVICE_NAME).map(d => ({ ...d, runtime })))
  .sort((a, b) => a.runtime.localeCompare(b.runtime, undefined, { numeric: true }))
  .at(-1)
if (match) process.stdout.write(match.udid)
NODE
}

ensure_software_keyboard() {
    local udid="$1"
    [[ -n "$udid" ]] || return 0

    local state
    state="$("$XCRUN" simctl list devices -j | UDID="$udid" node -e '
const d = Object.values(JSON.parse(require("fs").readFileSync(0, "utf8")).devices).flat()
  .find(x => x.udid === process.env.UDID)
process.stdout.write(d ? d.state : "")')"
    if [[ "$state" != "Booted" ]]; then
        "$XCRUN" simctl boot "$udid" >/dev/null 2>&1 || true
        "$XCRUN" simctl bootstatus "$udid" -b >/dev/null 2>&1 || true
    fi

    local seen
    seen="$("$XCRUN" simctl spawn "$udid" defaults read com.apple.keyboard.preferences \
        HardwareKeyboardLastSeen 2>/dev/null || true)"
    if [[ "$seen" != "1" ]]; then
        return 0
    fi

    echo "Simulator $udid remembers a hardware keyboard; restoring the on-screen keyboard (ADEV-214)."
    "$XCRUN" simctl spawn "$udid" defaults write com.apple.keyboard.preferences \
        HardwareKeyboardLastSeen -bool false
    "$XCRUN" simctl shutdown "$udid" >/dev/null 2>&1 || true
    "$XCRUN" simctl boot "$udid"
    "$XCRUN" simctl bootstatus "$udid" -b >/dev/null
}
