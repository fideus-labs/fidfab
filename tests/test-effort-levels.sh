#!/usr/bin/env bash
# test-effort-levels.sh — offline check of the effort level every agent stage runs at.
#
# Policy: Claude implementation stages run at xhigh, Claude and Codex review stages at
# high, every other Claude and Codex stage at medium, and Gemini at medium. Every agent
# node must set its effort explicitly so that no stage inherits an agent default.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$here"

# <file>:<node> pairs that are not medium.
declare -A expected=(
  [.fabro/workflows/small/workflow.fabro:implement]=xhigh
  [.fabro/workflows/medium/workflow.fabro:implement]=xhigh
  [.fabro/workflows/large/workflow.fabro:critique]=high
  [components/claude-review.fabro:review]=high
  [components/codex-review.fabro:review]=high
  [components/security-review.fabro:review]=high
  [components/coderabbit-review.fabro:review]=high
  [components/coderabbit-review.fabro:fallback]=high
  [components/personal-data-audit.fabro:audit]=high
)

status=0
fail() { echo "FAIL: $*" >&2; status=1; }
declare -A seen=()
agents=0

# One line per agent node: <file> <node> <claude|codex|gemini> <effort or ->.
while read -r file node agent effort; do
  agents=$((agents + 1))
  key="$file:$node"
  seen[$key]=1
  want="${expected[$key]:-medium}"
  [[ "$agent" == gemini && "$want" != medium ]] && fail "$key: Gemini nodes run at medium"
  [[ "$effort" == "$want" ]] || fail "$key ($agent): effort is '$effort', expected '$want'"
done < <(
  awk '
    function flush() {
      if (agent != "") print FILENAME, node, agent, (effort == "" ? "-" : effort)
      agent = ""; effort = ""
    }
    FNR == 1 { flush(); node = "" }
    /^[[:space:]]*[A-Za-z_][A-Za-z0-9_]*[[:space:]]+\[/ { flush(); node = $1 }
    /acp\.command="fidfab-claude-acp/ { agent = "claude" }
    /acp\.command="fidfab-codex-acp/  { agent = "codex" }
    /provider="litellm"/              { agent = "gemini" }
    match($0, /--effort [a-z]+/)               { effort = substr($0, RSTART + 9, RLENGTH - 9) }
    match($0, /reasoning_effort="[a-z]+"/)     { effort = substr($0, RSTART + 18, RLENGTH - 19) }
    END { flush() }
  ' components/*.fabro .fabro/workflows/*/workflow.fabro
)

[[ $agents -gt 0 ]] || fail "no agent nodes found"
for key in "${!expected[@]}"; do
  [[ -n "${seen[$key]:-}" ]] || fail "$key: expected node not found"
done

# Gemini default for Fabro-native nodes without an explicit model.
for toml in .fabro/workflows/*/workflow.toml; do
  got="$(awk '/^\[/ { in_controls = ($0 == "[run.model.controls]") }
              in_controls && /^reasoning_effort[[:space:]]*=/ { gsub(/[" ]/, "", $0); sub(/^.*=/, "", $0); print }' "$toml")"
  [[ "$got" == medium ]] || fail "$toml: [run.model.controls] reasoning_effort is '$got', expected 'medium'"
done

# Default for Codex invocations that pass no --effort.
grep -qx 'model_reasoning_effort = "medium"' docker/config/codex-config.toml \
  || fail "docker/config/codex-config.toml: model_reasoning_effort is not medium"

[[ $status -eq 0 ]] && echo "effort levels: $agents agent nodes OK"
exit $status
