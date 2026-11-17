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

# Prints one line per agent node in the given DOT files.
scan_nodes() {
  awk '
    # A node is an agent when it has a prompt: an ACP node is Claude or Codex by its
    # acp.command, any other prompt node is Fabro-native (Gemini via [run.model] or an
    # explicit provider). Effort is read only from the attribute that backend honours.
    function flush() {
      if (node != "" && prompt) {
        if (acp) agent = (cmd ~ /^fidfab-claude-acp( |$)/ ? "claude" : cmd ~ /^fidfab-codex-acp( |$)/ ? "codex" : "unknown-acp")
        else agent = "gemini"
        effort = "-"
        if (agent == "claude" || agent == "codex") {
          if (match(cmd, /(^| )--effort [^[:space:]"]+/)) { e = substr(cmd, RSTART, RLENGTH); sub(/^ ?--effort /, "", e); effort = e }
        } else if (agent == "gemini" && rfx != "") effort = rfx
        print FILENAME, node, agent, effort
      }
      node = ""; prompt = 0; acp = 0; cmd = ""; rfx = ""
    }
    FNR == 1 { flush() }
    /^[[:space:]]*\/\// { next }
    /^[[:space:]]*[A-Za-z_][A-Za-z0-9_]*[[:space:]]*->/ { flush(); next }
    /^[[:space:]]*[A-Za-z_][A-Za-z0-9_]*[[:space:]]*\[/ {
      flush()
      name = $0; sub(/^[[:space:]]*/, "", name); sub(/[[:space:]]*\[.*$/, "", name)
      if (name != "graph" && name != "node" && name != "edge") node = name
    }
    node == "" { next }
    /(^|[[:space:],\[])prompt="/ { prompt = 1 }
    /backend="acp"/ { acp = 1 }
    match($0, /acp\.command="[^"]*"/)      { cmd = substr($0, RSTART + 13, RLENGTH - 14) }
    match($0, /reasoning_effort="[^"]*"/)  { rfx = substr($0, RSTART + 18, RLENGTH - 19) }
    END { flush() }
  ' "$@"
}

# Self-test of the scanner on a fixture with the cases it must not be fooled by.
fixture="$(mktemp)"; trap 'rm -f "$fixture"' EXIT
cat > "$fixture" <<'DOT'
digraph T {
  graph [label="t"]
  native [label="x", prompt="@p.md"]
  suffix [backend="acp", acp.command="fidfab-claude-acp --model opus --effort medium-high",
          prompt="@p.md"]
  crossed [backend="acp", acp.command="fidfab-codex-acp --model luna", reasoning_effort="medium",
           prompt="@p.md"]
  other [backend="acp", acp.command="some-acp --effort medium", prompt="@p.md"]
  ok[backend="acp", acp.command="fidfab-codex-acp --effort high",
     prompt="@p.md"]
  // ghost [backend="acp", acp.command="fidfab-claude-acp --effort medium", prompt="@p.md"]
  tool [script="true"]
  ok -> tool [label="x", prompt="@p.md"]
}
DOT
got="$(scan_nodes "$fixture" | cut -d' ' -f2-)"
want="native gemini -
suffix claude medium-high
crossed codex -
other unknown-acp -
ok codex high"
[[ "$got" == "$want" ]] || { echo "FAIL: scanner self-test; got:" >&2; echo "$got" >&2; exit 1; }

status=0
fail() { echo "FAIL: $*" >&2; status=1; }
declare -A seen=()
agents=0

# One line per agent node: <file> <node> <claude|codex|gemini|unknown-acp> <effort or ->.
while read -r file node agent effort; do
  agents=$((agents + 1))
  key="$file:$node"
  seen[$key]=1
  want="${expected[$key]:-medium}"
  [[ "$agent" == unknown-acp ]] && { fail "$key: ACP node with an unrecognised acp.command"; continue; }
  [[ "$agent" == gemini && "$want" != medium ]] && fail "$key: Gemini nodes run at medium"
  [[ "$effort" == "$want" ]] || fail "$key ($agent): effort is '$effort', expected '$want'"
done < <(
  scan_nodes components/*.fabro .fabro/workflows/*/workflow.fabro
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
