#!/bin/bash
# test-core.sh — the two test suites nothing ran until AITD-541:
#   - Packages/AstridCore's own tests (the Swift layer over astrid-core: CoreSession, the rules
#     bridge, markdown), via `swift test`. The package resolves the pinned XCFramework release,
#     or the local build beside Package.swift when there is one.
#   - the UniFFI binding crate (astrid-core's `crates/astrid-uniffi`, AITD-643) still compiles at
#     the pin, via `cargo check`. Its tests run in astrid-core's CI: cargo refuses `cargo test -p`
#     for a package outside the workspace.
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
    if cargo check --manifest-path core/Cargo.toml -p astrid-uniffi >"$LOG" 2>&1; then
        echo "✓ astrid-uniffi Rust: builds at the pinned core"
    else
        echo "✗ astrid-uniffi Rust check failed:"; grep -E "^error" "$LOG" | head -10; status=1
    fi
else
    echo "⚠ cargo not found — astrid-uniffi Rust check SKIPPED (install Rust: https://rustup.rs)"
fi
exit $status
