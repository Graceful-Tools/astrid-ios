#!/bin/bash
#
# xcresult-summary.sh — what a test run actually did, read from its result bundles (AITD-524).
#
#   ./scripts/xcresult-summary.sh counts   <bundle.xcresult>...   # "41 passed, 3 skipped, 1 failed"
#   ./scripts/xcresult-summary.sh failures <bundle.xcresult>...   # one "<test> — <why>" per failure
#
# run-tests.sh used to count log LINES containing "passed" / "skipped", which is not a test
# count. The bundle knows the real numbers. A bundle that is missing or unreadable (a run that
# died before writing one) is skipped rather than fatal: this reports, it never decides a gate.
set -u

MODE="${1:-}"; shift || true
case "$MODE" in counts|failures) ;; *) echo "usage: $0 counts|failures <bundle.xcresult>..." >&2; exit 2 ;; esac

summaries=()
for bundle in "$@"; do
  [ -d "$bundle" ] || continue
  json=$(xcrun xcresulttool get test-results summary --path "$bundle" 2>/dev/null) || continue
  summaries+=("$json")
done

printf '%s\n\0' "${summaries[@]+"${summaries[@]}"}" | MODE="$MODE" node -e '
  const parts = require("fs").readFileSync(0, "utf8").split("\0").map(s => s.trim()).filter(Boolean);
  const all = parts.map(p => { try { return JSON.parse(p); } catch { return null; } }).filter(Boolean);
  if (process.env.MODE === "counts") {
    const sum = k => all.reduce((n, s) => n + (s[k] || 0), 0);
    console.log(`${sum("passedTests")} passed, ${sum("skippedTests")} skipped, ${sum("failedTests")} failed`);
  } else {
    for (const s of all) for (const f of s.testFailures || []) {
      const why = String(f.failureText || "").split("\n")[0].trim();
      console.log(`${f.testIdentifierString || f.testName || "?"} — ${why}`);
    }
  }
'
