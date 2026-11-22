#!/bin/bash
#
# test-sim-keyboard.sh — scripts/lib/sim-keyboard.sh restores the on-screen keyboard when, and
# only when, the simulator remembers a hardware one (ADEV-214), against a fake `xcrun`.
#
# A ⌘A in one UI run leaves HardwareKeyboardLastSeen set on the device, and every later run then
# tests a keyboard that is never drawn: CommentUITests' drag failed in CI that way.
set -u
cd "$(dirname "$0")/.."

dir="$(mktemp -d)"
trap 'rm -rf "$dir"' EXIT
cat > "$dir/xcrun" <<'FAKE'
#!/bin/bash
echo "$*" >> "$FAKE_LOG"
case "$*" in
  "simctl list devices available -j"|"simctl list devices -j")
    cat <<JSON
{"devices":{
 "com.apple.CoreSimulator.SimRuntime.iOS-26-2":[{"udid":"OLD","name":"iPhone 17","state":"Shutdown","isAvailable":true}],
 "com.apple.CoreSimulator.SimRuntime.iOS-27-2":[{"udid":"NEW","name":"iPhone 17","state":"Booted","isAvailable":true}]}}
JSON
    ;;
  *"defaults read com.apple.keyboard.preferences HardwareKeyboardLastSeen") echo "$FAKE_SEEN" ;;
esac
FAKE
chmod +x "$dir/xcrun"

run() { # $1 = flag value the fake reports; prints the simctl calls made
  : > "$dir/log"
  FAKE_LOG="$dir/log" FAKE_SEEN="$1" XCRUN="$dir/xcrun" bash -c \
    '. scripts/lib/sim-keyboard.sh; ensure_software_keyboard NEW' >/dev/null
  cat "$dir/log"
}
fail() { echo "✗ sim-keyboard: $1"; exit 1; }

udid="$(XCRUN="$dir/xcrun" FAKE_LOG=/dev/null bash -c '. scripts/lib/sim-keyboard.sh; sim_udid_for_destination "platform=iOS Simulator,name=iPhone 17,OS=latest"')"
[ "$udid" = NEW ] || fail "a named destination resolved to '$udid', not the newest runtime's device"
udid="$(XCRUN="$dir/xcrun" bash -c '. scripts/lib/sim-keyboard.sh; sim_udid_for_destination "platform=iOS Simulator,id=ABC-123"')"
[ "$udid" = ABC-123 ] || fail "an id= destination resolved to '$udid'"

calls="$(run 1)"
grep -q "defaults write com.apple.keyboard.preferences HardwareKeyboardLastSeen -bool false" <<<"$calls" \
  || fail "a remembered hardware keyboard was not cleared"
grep -q "simctl shutdown NEW" <<<"$calls" && grep -q "simctl boot NEW" <<<"$calls" \
  || fail "the flag was cleared without the reboot it needs to take effect"

calls="$(run 0)"
grep -qE "defaults write|simctl shutdown" <<<"$calls" \
  && fail "a simulator already on its software keyboard was rebooted anyway"

echo "✓ sim-keyboard: a remembered hardware keyboard is cleared with one reboot, and only then"
