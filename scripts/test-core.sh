#!/bin/bash
# test-core.sh — the two test suites nothing ran until AITD-541:
#   - Packages/AstridCore's own tests (the Swift layer over astrid-core: CoreSession, the rules
#     bridge, markdown), via `swift test`. The package resolves the pinned XCFramework release,
#     or the local build beside Package.swift when there is one.
#   - core/astrid-apple's Rust tests (the UniFFI binding layer), via `cargo test`.
# A missing toolchain is a visible skip, never a silent pass.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
LOG="$(mktemp -t test-core)"
trap 'rm -f "$LOG"' EXIT
status=0

if command -v swift >/dev/null 2>&1; then
    if swift test --package-path Packages/AstridCore >"$LOG" 2>&1; then
        echo "✓ AstridCore package: $(grep -Eo 'Executed [0-9]+ tests, with [0-9]+ failures' "$LOG" | tail -1)"
    else
        echo "✗ AstridCore package tests failed:"; grep -E "error|failed" "$LOG" | head -10; status=1
    fi
else
    echo "⚠ swift not found — AstridCore package tests SKIPPED"
fi

if command -v cargo >/dev/null 2>&1; then
    if cargo test --manifest-path core/Cargo.toml >"$LOG" 2>&1; then
        echo "✓ astrid-apple Rust: $(grep -E '^test result' "$LOG" | head -1)"
    else
        echo "✗ astrid-apple Rust tests failed:"; grep -E "^test .*FAILED|error" "$LOG" | head -10; status=1
    fi
else
    echo "⚠ cargo not found — astrid-apple Rust tests SKIPPED (install Rust: https://rustup.rs)"
fi
exit $status
