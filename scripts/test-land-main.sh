#!/bin/zsh
# test-land-main.sh — self-test for scripts/land-main.sh against a throwaway origin and a stub gh.
set -u
HERE="${0:A:h}"
LAND="$HERE/land-main.sh"
pass=0; failed=0
check() { if eval "$2"; then print -r -- "  ✓ $1"; pass=$((pass+1)); else print -r -- "  ✗ $1"; failed=$((failed+1)); fi; }

T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.invalid GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.invalid

# A stub gh: records calls; `pr merge` moves origin main to the land/* branch.
cat > "$T/gh" <<'EOF'
#!/bin/zsh
print -r -- "$*" >> "$STUB_LOG"
case "$1 $2" in
  "pr list") ;;
  "pr create") print -r -- "https://github.com/x/y/pull/7" ;;
  "pr checks") print -r -- "socket / socket-package-gate	${STUB_CHECK:-pass}	11s	https://x" ;;
  "pr merge")
    b=$(git --git-dir="$STUB_ORIGIN" for-each-ref --format='%(refname)' 'refs/heads/land/*' | head -1)
    git --git-dir="$STUB_ORIGIN" update-ref refs/heads/main "$b" ;;
esac
EOF
chmod +x "$T/gh"

setup() {
  rm -rf "$T/origin.git" "$T/work"; : > "$T/log"
  git init -q --bare -b main "$T/origin.git"
  git clone -q "$T/origin.git" "$T/work" 2>/dev/null
  ( cd "$T/work" && git commit -q --allow-empty -m base && git push -q origin main \
      && git push -q origin main:iosdev main:macdev && git commit -q --allow-empty -m "ADEV-1 Fix a thing" )
}
run() { ( cd "$T/work" && LAND_GH="$T/gh" LAND_POLL_SECONDS=0 LAND_WAIT_SECONDS=0 \
          STUB_LOG="$T/log" STUB_ORIGIN="$T/origin.git" zsh "$LAND" "$@" ) }
origin() { git --git-dir="$T/origin.git" rev-parse "refs/heads/$1" 2>/dev/null; }
local_main() { git -C "$T/work" rev-parse main; }

print -r -- "land-main.sh"
setup; out=$(run)
check "lands main through a PR" '[[ "$out" == "RESULT: OK — PR #7 merged"* ]]'
check "origin main is local main" '[ "$(origin main)" = "$(local_main)" ]'
check "iosdev and macdev follow it" '[ "$(origin iosdev)" = "$(local_main)" ] && [ "$(origin macdev)" = "$(local_main)" ]'
check "the PR is merged with a merge commit" 'grep -q "pr merge 7 .*--merge" "$T/log"'
check "only required checks are waited on" 'grep -q "pr checks 7 .*--required" "$T/log"'

setup; before=$(origin main); out=$(STUB_CHECK=fail run)
check "a failed required check stops it" '[[ "$out" == "RESULT: FAILED — PR #7: a required check did not pass"* ]]'
check "and nothing moves" '[ "$(origin main)" = "$before" ] && [ "$(origin iosdev)" = "$before" ]'

setup; before=$(origin iosdev); out=$(run --no-build)
check "--no-build lands main only" '[[ "$out" == *"no build" ]] && [ "$(origin main)" = "$(local_main)" ] && [ "$(origin iosdev)" = "$before" ]'

setup; print -r -- x > "$T/work/f"; git -C "$T/work" add f; out=$(run)
check "a dirty tree is refused" '[[ "$out" == "RESULT: FAILED — uncommitted changes"* ]]'

setup; git -C "$T/work" push -q origin main; : > "$T/log"; out=$(run)
check "nothing to land opens no PR but still builds" '[[ "$out" == "RESULT: OK — main already on origin"* ]] && ! grep -q "pr create" "$T/log" && [ "$(origin iosdev)" = "$(local_main)" ]'

print -r -- "  $pass passed, $failed failed"
[ "$failed" = 0 ]
