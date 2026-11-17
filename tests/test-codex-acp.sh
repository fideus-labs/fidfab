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

# Alias resolution and the baked config default, checked offline against the installed
# wrapper and config (CI runs the same test against the repository files).
# The Dockerfile bakes docker/config/codex-config.toml at /root/.codex/config.toml; check that
# file even when CODEX_HOME points elsewhere (CODEX_HOME is only used for auth.json below).
"$here/test-codex-model.sh" "$(command -v fidfab-codex-acp)" /root/.codex/config.toml
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
