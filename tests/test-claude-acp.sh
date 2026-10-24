#!/usr/bin/env bash
# Verify the Claude Code ACP adapter inside the fidfab image.
#
# Without credentials only the protocol handshake is checked. With
# CLAUDE_CODE_OAUTH_TOKEN (or ANTHROPIC_API_KEY) a one-line prompt is sent to
# the configured "opus" alias and the answer is checked.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
echo "[claude-acp] adapter: $(command -v claude-agent-acp) ($(claude-agent-acp --version 2>/dev/null || echo '?'))"
echo "[claude-acp] claude:  $(claude --version 2>/dev/null | head -1)"
if [[ -z "${CLAUDE_CODE_OAUTH_TOKEN:-}${ANTHROPIC_API_KEY:-}" ]]; then
  echo "[claude-acp] no credentials; handshake only"
  node "$here/acp-smoke.mjs" --handshake-only --timeout 60 -- fidfab-claude-acp --model opus
else
  node "$here/acp-smoke.mjs" --timeout 240 -- fidfab-claude-acp --model opus
fi
echo "[claude-acp] OK"
