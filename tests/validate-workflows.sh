#!/usr/bin/env bash
# validate-workflows.sh — offline validation of every fidfab workflow with `fabro validate`,
# plus the offline lints (model aliases, history rewrite after the steward), the self-test
# of the history-rewrite lint, the history-rewrite push helper's test, and a check that the
# vendored component copies are in sync.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export PATH="$HOME/.fabro/bin:$PATH"

# Model aliases and the history rewrite first: offline, so they report even where fabro
# is not installed.
"$here/tests/check-model-aliases.sh"
"$here/tests/check-history-rewrite.sh"
# Run here rather than as CI steps of their own: CI runs this script, and the run's push
# token cannot change .github/workflows (no workflows permission).
"$here/tests/test-history-rewrite.sh"
"$here/tests/test-rewrite-push.sh"
command -v fabro >/dev/null || { echo "fabro not installed: curl -fsSL https://fabro.sh/install.sh | sh"; exit 1; }
"$here/scripts/sync-components.sh" --check
status=0
for wf in "$here"/.fabro/workflows/*/workflow.toml; do
  echo "=== $wf"
  fabro validate --no-upgrade-check "$wf" || status=1
done
exit $status
