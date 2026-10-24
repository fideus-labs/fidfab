#!/usr/bin/env bash
# test-image.sh — run the fidfab image test suite from the host.
#
# Usage: tests/test-image.sh [image] [test...]
#   tests/test-image.sh                      # all tests against fidfab:latest
#   tests/test-image.sh fidfab:latest tools  # one test
#
# Credentials are passed through from the host environment when present so the
# authenticated variants of the tests run:
#   CLAUDE_CODE_OAUTH_TOKEN / ANTHROPIC_API_KEY, CODEX_AUTH_JSON_B64 /
#   OPENAI_API_KEY, CODERABBIT_API_KEY / CODERABBIT_REGION.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
image="${1:-fidfab:latest}"; shift || true
tests=("$@"); [[ ${#tests[@]} -eq 0 ]] && tests=(tools coderabbit claude-acp codex-acp)

envs=()
for v in CLAUDE_CODE_OAUTH_TOKEN ANTHROPIC_API_KEY CODEX_AUTH_JSON_B64 OPENAI_API_KEY CODERABBIT_API_KEY CODERABBIT_REGION FIDFAB_MODEL_OPUS FIDFAB_MODEL_FABLE FIDFAB_MODEL_LUNA; do
  [[ -n "${!v:-}" ]] && envs+=(-e "$v")
done

status=0
for t in "${tests[@]}"; do
  echo "=== $t ($image)"
  if docker run --rm "${envs[@]}" -v "$here:/fidfab-tests:ro" -w /tmp "$image" bash "/fidfab-tests/test-$t.sh"; then
    echo "=== $t: PASS"
  else
    echo "=== $t: FAIL"; status=1
  fi
done
exit $status
