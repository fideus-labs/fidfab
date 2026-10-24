#!/usr/bin/env bash
# Render each workflow graph to docs/graphs/<name>.svg with `fabro graph`.
# `fabro graph` validates the run configuration first, which requires a ready
# LLM provider on the local Fabro server (for example the DeepSeek key stored
# by `scripts/setup.sh deepseek`).
set -euo pipefail
cd "$(dirname "$0")/.."
export PATH="$HOME/.fabro/bin:$PATH"
mkdir -p docs/graphs
for dir in .fabro/workflows/*/; do
  name="$(basename "$dir")"
  fabro graph --no-upgrade-check "$dir/workflow.toml" > "docs/graphs/$name.svg" \
    2> >(grep -v 'ignored.workflow_toml' >&2 || true)
  echo "docs/graphs/$name.svg"
done
