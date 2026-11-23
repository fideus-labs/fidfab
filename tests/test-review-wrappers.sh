#!/usr/bin/env bash
# test-review-wrappers.sh — host-side check of the Codex and CodeRabbit wrappers. They restore
# their credentials from the secrets when the sandbox lacks them, as after `fabro fork`: the
# fork starts in a fresh sandbox, and fidfab-bootstrap ran in the parent's. And
# `fidfab-coderabbit review` fails unless CodeRabbit finished the review, so that a usage
# limit stops the workflow at a gate. Stubbed codex-acp and coderabbit; the repository's
# fidfab-bootstrap does the restoring.
set -euo pipefail
cd "$(dirname "$0")/.."
bin="$PWD/docker/rootfs/usr/local/bin"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/stub"

# codex-acp prints the auth.json it finds, or answers one request with $ACP_ANSWER; coderabbit is logged in once
# `auth login` ran.
cat > "$tmp/stub/codex-acp" <<'EOF'
#!/bin/sh
if [ -n "$ACP_SPLIT" ]; then printf '{"t":"\303'; sleep 0.2; printf '\251"}\n'  # one character, two writes
elif [ -n "$ACP_ANSWER" ]; then read -r _; echo "$ACP_ANSWER"
else cat "$CODEX_HOME/auth.json"; fi
EOF
cat > "$tmp/stub/coderabbit" <<'EOF'
#!/bin/sh
case "$1 $2" in
  "auth login") touch "$HOME/logged-in"; echo login >> "$HOME/calls" ;;
  "review --agent") printf '%s\n' "$CR_REVIEW" ;;
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
mkdir -p "$tmp"/h{1,2,3,4,5,6,7}/.codex; touch "$tmp/h3/logged-in"
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

# Fabro authenticates an agent that advertises sign-in methods, by API key only: signed in, Codex advertises none.
answer='{"jsonrpc":"2.0","id":1,"result":{"protocolVersion":1,"authMethods":[{"id":"api-key"}]}}'
echo renewed > "$tmp/h6/.codex/auth.json"
check "codex: signed in, initialize advertises no sign-in method" \
  "$(echo '{"id":1,"method":"initialize"}' | run "$tmp/h6" ACP_ANSWER="$answer" -- fidfab-codex-acp)" \
  '{"jsonrpc":"2.0","id":1,"result":{"protocolVersion":1,"authMethods":[]}}'
check "codex: signed in, a character split across two writes arrives whole" \
  "$(run "$tmp/h6" ACP_SPLIT=1 -- fidfab-codex-acp)" '{"t":"é"}'
check "codex: not signed in, initialize keeps its sign-in methods" \
  "$(echo '{"id":1,"method":"initialize"}' | run "$tmp/h7" ACP_ANSWER="$answer" -- fidfab-codex-acp)" "$answer"

done_line='{"type":"complete","status":"review_completed","findings":0}'
check "coderabbit review: a finished review is saved and passes" \
  "$(run "$tmp/h1" CR_REVIEW="$done_line" -- fidfab-coderabbit review >/dev/null && cat "$tmp/h1/.fidfab/reviews/coderabbit.md")" \
  "$done_line"
check "coderabbit review: a review a usage limit ended fails" \
  "$(run "$tmp/h1" CR_REVIEW='{"type":"error","phase":"review","status":"rate_limited"}' -- fidfab-coderabbit review >/dev/null || echo "exit $?")" \
  "exit 1"
exit $fail
