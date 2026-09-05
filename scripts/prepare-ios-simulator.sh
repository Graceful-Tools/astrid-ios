#!/bin/bash

set -euo pipefail

DEVICE_NAME="${ASTRID_SIMULATOR_NAME:-iPhone 17}"
DEVICES_JSON="$(xcrun simctl list devices available -j)"

SELECTED="$(
    DEVICES_JSON="${DEVICES_JSON}" DEVICE_NAME="${DEVICE_NAME}" node <<'NODE'
const devices = JSON.parse(process.env.DEVICES_JSON).devices
const matches = Object.entries(devices)
  .flatMap(([runtime, entries]) =>
    entries
      .filter(device => device.isAvailable && device.name === process.env.DEVICE_NAME)
      .map(device => ({ ...device, runtime }))
  )
  .sort((a, b) => a.runtime.localeCompare(b.runtime, undefined, { numeric: true }))

const selected = matches.find(device => device.state === "Booted") ?? matches.at(-1)
if (!selected) process.exit(1)
process.stdout.write(`${selected.udid} ${selected.state}`)
NODE
)"
read -r UDID STATE <<< "${SELECTED}"

if [[ -z "${UDID:-}" ]]; then
    echo "No available simulator named '${DEVICE_NAME}'." >&2
    exit 1
fi

if [[ "${STATE}" == "Shutdown" ]]; then
    echo "Booting ${DEVICE_NAME} (${UDID})..."
    xcrun simctl boot "${UDID}"
elif [[ "${STATE}" == "Booted" ]]; then
    echo "Reusing booted ${DEVICE_NAME} (${UDID})."
else
    echo "Waiting for ${DEVICE_NAME} (${UDID}) in state ${STATE}."
fi

xcrun simctl bootstatus "${UDID}" -b
DESTINATION="platform=iOS Simulator,id=${UDID}"

if [[ -n "${GITHUB_ENV:-}" ]]; then
    echo "DESTINATION=${DESTINATION}" >> "${GITHUB_ENV}"
fi

echo "${DESTINATION}"
