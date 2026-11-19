#!/bin/bash
#
# test-uitest-session.sh — the per-run test-account mint must work where there is no .env.local.
#
# ADEV-117: once the self-hosted runner came back, the Mac UI job died before a single test with
# `uitest-session.sh: line 52: env_flag[@]: unbound variable`. CI has no astrid-web/.env.local
# (its secrets arrive as environment), so `env_flag` stayed an empty array, and macOS's
# /bin/bash 3.2 treats "${empty[@]}" as unbound under `set -u` — which run-mac-tests.sh sets.
# Every local run has the file, so no local gate ever took that branch.
#
# Runs the real helper under /bin/bash with `set -u`, against a fake npx.
set -u
cd "$(dirname "$0")/.."
REPO="$PWD"

tmp="$(mktemp -d "${TMPDIR:-/tmp}/uitest-session.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/web"
cat > "$tmp/bin/npx" <<'EOF'
#!/bin/bash
echo "npx $*"
EOF
chmod +x "$tmp/bin/npx"

run_mint() {
  PATH="$tmp/bin:$PATH" /bin/bash -c '
    set -euo pipefail
    PROJECT_DIR="$1"; ASTRID_WEB_DIR="$2"
    source "$1/scripts/lib/uitest-session.sh"
    uitest_account --run gha-1-1
  ' _ "$REPO" "$tmp/web" 2>&1
}

fail=0

out="$(run_mint)"; status=$?
if [ "$status" -ne 0 ] || [[ "$out" != "npx tsx scripts/uitest-account.ts --run gha-1-1" ]]; then
  echo "✗ without .env.local (CI) the mint must run tsx with no --env-file; got ($status): $out"
  fail=1
fi

touch "$tmp/web/.env.local"
out="$(run_mint)"; status=$?
if [ "$status" -ne 0 ] || [[ "$out" != "npx tsx --env-file=.env.local scripts/uitest-account.ts --run gha-1-1" ]]; then
  echo "✗ with .env.local the mint must pass --env-file; got ($status): $out"
  fail=1
fi

[ "$fail" -eq 0 ] || exit 1
echo "✓ uitest-session: the mint runs with and without .env.local under set -u"
