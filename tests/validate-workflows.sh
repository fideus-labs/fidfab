#!/usr/bin/env bash
# validate-workflows.sh — offline validation of every fidfab workflow with `fabro validate`,
# plus a check that the vendored component copies are in sync.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export PATH="$HOME/.fabro/bin:$PATH"
command -v fabro >/dev/null || { echo "fabro not installed: curl -fsSL https://fabro.sh/install.sh | sh"; exit 1; }
"$here/scripts/sync-components.sh" --check
status=0
for wf in "$here"/.fabro/workflows/*/workflow.toml; do
  echo "=== $wf"
  fabro validate --no-upgrade-check "$wf" || status=1
done
exit $status
