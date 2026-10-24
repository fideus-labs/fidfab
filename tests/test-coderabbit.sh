#!/usr/bin/env bash
# Verify the CodeRabbit CLI inside the fidfab image.
#
# Always: the binary runs and reports a version. With CODERABBIT_API_KEY: logs
# in non-interactively, checks `auth status`, and runs an agent-mode review on
# a throwaway git repository with one uncommitted change.
set -euo pipefail
echo "[coderabbit] binary: $(command -v coderabbit) ($(coderabbit --version 2>/dev/null | head -1 || echo '?'))"
if [[ -z "${CODERABBIT_API_KEY:-}" ]]; then
  echo "[coderabbit] CODERABBIT_API_KEY not set; skipping authenticated checks"
  echo "[coderabbit] OK (unauthenticated)"
  exit 0
fi
coderabbit auth login ${CODERABBIT_REGION:+--region "$CODERABBIT_REGION"} --api-key "$CODERABBIT_API_KEY"
coderabbit auth status --agent
fidfab-coderabbit available

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
git -C "$tmp" init -q -b main
cat > "$tmp/div.py" <<'PY'
def divide(a, b):
    return a / b
PY
git -C "$tmp" add -A && git -C "$tmp" -c user.name=fidfab -c user.email=fidfab@fideus.io commit -qm "init"
cat > "$tmp/div.py" <<'PY'
def divide(a, b):
    # TODO handle b == 0
    result = a / b
    print("result is " + result)
    return result
PY
( cd "$tmp" && coderabbit review --agent --type uncommitted | tee "$tmp/review.txt" )
if [[ -s "$tmp/review.txt" ]]; then echo "[coderabbit] review produced output"; else echo "[coderabbit] empty review output" >&2; exit 1; fi
echo "[coderabbit] OK"
