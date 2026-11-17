#!/usr/bin/env bash
# validate-workflows.sh — offline validation of every fidfab workflow with `fabro validate`,
# plus a check that the vendored component copies are in sync.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export PATH="$HOME/.fabro/bin:$PATH"

# Every `fidfab-<agent>-acp --model <alias>` in a workflow or component must name an alias
# the wrapper resolves; an unknown name is passed to the agent as a literal model ID and the
# stage fails only at run time. Runs before the fabro check so it works offline.
bin="$here/docker/rootfs/usr/local/bin"
alias_status=0
while IFS=: read -r file _ ref; do
  wrapper="${ref%% *}"; alias="${ref##* }"
  if [[ ! -f "$bin/$wrapper" ]]; then
    echo "unknown wrapper $wrapper in $file"; alias_status=1
  elif ! grep -Eq "^[[:space:]]*([^)[:space:]]*\|)?$alias(\|[^)]*)?\)" "$bin/$wrapper"; then
    echo "$file: $wrapper has no model alias '$alias'"; alias_status=1
  fi
done < <(grep -rnoE --include='*.fabro' 'fidfab-[a-z]+-acp --model [A-Za-z0-9._-]+' \
           "$here/components" "$here/.fabro/workflows")
[[ $alias_status -eq 0 ]] || exit 1
command -v fabro >/dev/null || { echo "fabro not installed: curl -fsSL https://fabro.sh/install.sh | sh"; exit 1; }
"$here/scripts/sync-components.sh" --check
status=0
for wf in "$here"/.fabro/workflows/*/workflow.toml; do
  echo "=== $wf"
  fabro validate --no-upgrade-check "$wf" || status=1
done
exit $status
