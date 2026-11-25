#!/usr/bin/env bash
# validate-workflows.sh — offline validation of every fidfab workflow with `fabro validate`,
# plus the model alias, pipeline order and history rewrite checks and a check that the
# vendored component copies are in sync.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export PATH="$HOME/.fabro/bin:$PATH"

# Model aliases first: offline, so it reports even where fabro is not installed.
"$here/tests/check-model-aliases.sh"
# Offline as well: the verification pipeline runs its stages in one order, and the history
# rewrite follows the PR steward in every workflow.
"$here/tests/test-pipeline-order.sh"
"$here/tests/test-logical-commits.sh"
# A failed stage must end the run, not hand on to the next stage (Fabro's default).
for wf in "$here"/.fabro/workflows/*/workflow.fabro; do
  grep -qE '^ *graph \[.*on_failure="exit"' "$wf" || { echo "$wf: graph [...] lacks on_failure=\"exit\"" >&2; exit 1; }
done
command -v fabro >/dev/null || { echo "fabro not installed: curl -fsSL https://fabro.sh/install.sh | sh"; exit 1; }
"$here/scripts/sync-components.sh" --check
status=0
for wf in "$here"/.fabro/workflows/*/workflow.toml; do
  echo "=== $wf"
  fabro validate --no-upgrade-check "$wf" || status=1
done
exit $status
