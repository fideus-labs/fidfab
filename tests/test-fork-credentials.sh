#!/usr/bin/env bash
# test-fork-credentials.sh — host-side check that the Codex and CodeRabbit wrappers restore
# their credentials from the secrets when the sandbox lacks them, as after `fabro fork`: the
# fork starts in a fresh sandbox, and fidfab-bootstrap ran in the parent's. Stubbed
# codex-acp and coderabbit; the repository's fidfab-bootstrap does the restoring.
set -euo pipefail
cd "$(dirname "$0")/.."
bin="$PWD/docker/rootfs/usr/local/bin"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/stub"

# codex-acp prints the auth.json it finds; coderabbit is logged in once `auth login` ran.
printf '#!/bin/sh\ncat "$CODEX_HOME/auth.json"\n' > "$tmp/stub/codex-acp"
cat > "$tmp/stub/coderabbit" <<'EOF'
#!/bin/sh
case "$1 $2" in
  "auth login") touch "$HOME/logged-in"; echo login >> "$HOME/calls" ;;
  "auth status") if [ -e "$HOME/logged-in" ]; then echo '{"status":"authenticated","authenticated":true}'
                 else echo '{"status":"not_authenticated","authenticated":false}'; fi ;;
esac
EOF
chmod +x "$tmp/stub/codex-acp" "$tmp/stub/coderabbit"

fail=0
check() { if [[ "$2" == "$3" ]]; then echo "ok   $1"; else echo "FAIL $1: got '$2', want '$3'"; fail=1; fi; }
# run HOME [VAR=value...] -- COMMAND...: in HOME, with no host credentials.
run() {
  local home="$1" envs=(); shift
  while [[ "$1" != -- ]]; do envs+=("$1"); shift; done; shift
  (cd "$home" && env -i PATH="$tmp/stub:$bin:$PATH" HOME="$home" "${envs[@]}" "$@" 2>/dev/null)
}
mkdir -p "$tmp"/h{1,2,3,4,5}/.codex; touch "$tmp/h3/logged-in"
echo renewed > "$tmp/h2/.codex/auth.json"; echo renewed > "$tmp/h5/.codex/auth.json"

secret="$(printf '{"OPENAI_API_KEY":"sk-test"}' | base64 -w0)"
check "codex: auth.json written from the secret, stdout left to ACP" \
  "$(run "$tmp/h1" CODEX_AUTH_JSON_B64="$secret" -- fidfab-codex-acp)" '{"OPENAI_API_KEY":"sk-test"}'
check "codex: auth.json is private" "$(stat -c %a "$tmp/h1/.codex/auth.json")" 600
check "codex: an auth.json Codex renewed is kept" \
  "$(run "$tmp/h5" CODEX_AUTH_JSON_B64="$secret" -- fidfab-codex-acp)" renewed
check "coderabbit: logs in again from the key, Codex's auth.json untouched" \
  "$(run "$tmp/h2" CODERABBIT_API_KEY=cr-test CODEX_AUTH_JSON_B64="$secret" -- fidfab-coderabbit available
     cat "$tmp/h2/calls" "$tmp/h2/.codex/auth.json")" \
  "$(printf 'coderabbit: available\nlogin\nrenewed')"
check "coderabbit: logged in already, no second login" \
  "$(run "$tmp/h3" CODERABBIT_API_KEY=cr-test -- fidfab-coderabbit available; cat "$tmp/h3/calls" 2>/dev/null || true)" \
  "coderabbit: available"
check "coderabbit: not_authenticated without a key is unavailable" \
  "$(run "$tmp/h4" -- fidfab-coderabbit available || echo "exit $?")" "exit 1"
exit $fail
