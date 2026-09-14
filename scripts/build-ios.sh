#!/bin/bash
# Build the iOS app for the simulator. `npm run build` (quiet) / `npm run build:verbose`.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/ios-destination.sh"
cd "$(dirname "$SCRIPT_DIR")"
QUIET=(-quiet)
[[ "${1:-}" == "--verbose" ]] && QUIET=()
exec xcodebuild build -scheme "Astrid App" -destination "$ASTRID_IOS_DESTINATION" "${QUIET[@]}"
