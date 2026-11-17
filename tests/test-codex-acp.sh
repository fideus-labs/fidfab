#!/usr/bin/env bash
# Verify the Codex ACP adapter inside the fidfab image.
#
# Without credentials only the protocol handshake is checked. With
# CODEX_AUTH_JSON_B64 (materialised by fidfab-bootstrap) or OPENAI_API_KEY a
# one-line prompt is sent to the configured "terra" alias and the answer checked.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
echo "[codex-acp] adapter: $(command -v codex-acp) ($(codex-acp --version 2>/dev/null || echo '?'))"
echo "[codex-acp] codex:   $(codex --version 2>/dev/null | head -1)"
export CODEX_HOME="${CODEX_HOME:-$HOME/.codex}"

# Alias resolution, checked offline with a stub adapter that prints the model
# fidfab-codex-acp selected.
stub="$(mktemp -d)"; trap 'rm -rf "$stub"' EXIT
printf '#!/bin/sh\nprintf "%%s\\n" "$CODEX_CONFIG"\n' > "$stub/codex-acp"; chmod +x "$stub/codex-acp"
expect_model() { # <expected id> <command...>
  local want="$1" got; shift
  got="$(cd "$stub" && PATH="$stub:$PATH" "$@")"
  [[ "$got" == *"\"model\":\"$want\""* ]] || { echo "[codex-acp] FAIL: expected model $want from '$*', got $got" >&2; exit 1; }
}
expect_model gpt-5.6-terra env -u FIDFAB_MODEL_TERRA fidfab-codex-acp --model terra
expect_model gpt-5.6-terra env -u FIDFAB_MODEL_TERRA fidfab-codex-acp
expect_model pinned-id env FIDFAB_MODEL_TERRA=pinned-id fidfab-codex-acp --model terra
expect_model other-id fidfab-codex-acp --model other-id
echo "[codex-acp] alias: terra -> ${FIDFAB_MODEL_TERRA:-gpt-5.6-terra}"
if [[ -n "${CODEX_AUTH_JSON_B64:-}" && ! -f "$CODEX_HOME/auth.json" ]]; then
  mkdir -p "$CODEX_HOME"; umask 077; printf '%s' "$CODEX_AUTH_JSON_B64" | base64 -d > "$CODEX_HOME/auth.json"
fi
if [[ ! -f "$CODEX_HOME/auth.json" && -z "${OPENAI_API_KEY:-}" ]]; then
  echo "[codex-acp] no credentials; handshake only"
  node "$here/acp-smoke.mjs" --handshake-only --timeout 60 -- fidfab-codex-acp --model terra
else
  node "$here/acp-smoke.mjs" --timeout 240 -- fidfab-codex-acp --model terra --effort low
fi
echo "[codex-acp] OK"
