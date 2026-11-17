#!/usr/bin/env bash
# test-effort-levels.sh — offline check of the effort level every agent stage runs at.
#
# Policy: Claude implementation stages run at xhigh, Claude and Codex review stages at
# high, every other Claude and Codex stage at medium, and Gemini at medium. Every agent
# node must set its effort explicitly so that no stage inherits an agent default, and
# carry one role word in its class from which the expected level is derived.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$here"

# The expected level is derived from the agent and the role word in the node's class
# (expected_effort below). Nodes whose class does not decide it go here as
# [<file>:<node>]=<level>; there are none today.
declare -A override=()

# Role words a node class may carry. An agent node without exactly one fails, so a new
# node cannot slip through at the default.
roles="implement review security verify plan git decision"

# expected_effort <agent> <role>
expected_effort() {
  case "$1:$2" in
    claude:implement) echo xhigh ;;
    claude:review | claude:security | codex:review | codex:security) echo high ;;
    *) echo medium ;;
  esac
}

# Prints one line per agent node in the given DOT files:
# <file> <node> <claude|codex|gemini|unknown-acp> <effort or -> <class words...>.
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
        print FILENAME, node, agent, effort (cls == "" ? "" : " " cls)
      }
      node = ""; prompt = 0; acp = 0; cmd = ""; rfx = ""; cls = ""
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
    match($0, /(^|[[:space:],\[])class="[^"]*"/) { c = substr($0, RSTART, RLENGTH); sub(/^.*class="/, "", c); sub(/"$/, "", c); cls = c }
    END { flush() }
  ' "$@"
}

# Self-test of the scanner on a fixture with the cases it must not be fooled by.
fixture="$(mktemp)"; trap 'rm -f "$fixture"' EXIT
cat > "$fixture" <<'DOT'
digraph T {
  graph [label="t"]
  native [label="x", class="gemini review", prompt="@p.md"]
  suffix [backend="acp", acp.command="fidfab-claude-acp --model opus --effort medium-high",
          class="claude opus implement", prompt="@p.md"]
  crossed [backend="acp", acp.command="fidfab-codex-acp --model luna", reasoning_effort="medium",
           prompt="@p.md"]
  other [backend="acp", acp.command="some-acp --effort medium", prompt="@p.md"]
  ok[backend="acp", acp.command="fidfab-codex-acp --effort high", class="codex review",
     prompt="@p.md"]
  lowrev [backend="acp", acp.command="fidfab-claude-acp --effort medium", class="claude review", prompt="@p.md"]
  norole [backend="acp", acp.command="fidfab-codex-acp --effort medium", prompt="@p.md"]
  // ghost [backend="acp", acp.command="fidfab-claude-acp --effort medium", prompt="@p.md"]
  tool [script="true"]
  ok -> tool [label="x", prompt="@p.md"]
}
DOT
got="$(scan_nodes "$fixture" | cut -d' ' -f2-)"
want="native gemini - gemini review
suffix claude medium-high claude opus implement
crossed codex -
other unknown-acp -
ok codex high codex review
lowrev claude medium claude review
norole codex medium"
[[ "$got" == "$want" ]] || { echo "FAIL: scanner self-test; got:" >&2; echo "$got" >&2; exit 1; }

status=0
fail() { echo "FAIL: $*" >&2; status=1; }

# check_nodes <dot files...>: checks every agent node against the policy; prints failures.
check_nodes() {
  local file node agent effort cls key role want w n
  while read -r file node agent effort cls; do
    key="$file:$node"
    echo "seen $key"
    [[ "$agent" == unknown-acp ]] && { echo "FAIL: $key: ACP node with an unrecognised acp.command"; continue; }
    role=""; n=0
    for w in $cls; do
      [[ " $roles " == *" $w "* ]] && { role="$w"; n=$((n + 1)); }
    done
    if [[ -n "${override[$key]:-}" ]]; then
      want="${override[$key]}"
    elif [[ $n -ne 1 ]]; then
      echo "FAIL: $key: class '$cls' must carry exactly one role word ($roles)"; continue
    else
      want="$(expected_effort "$agent" "$role")"
    fi
    [[ "$agent" == gemini && "$want" != medium ]] && echo "FAIL: $key: Gemini nodes run at medium"
    [[ "$effort" == "$want" ]] || echo "FAIL: $key ($agent ${role:-no role}): effort is '$effort', expected '$want'"
  done < <(scan_nodes "$@")
}

# Self-test of the policy on the fixture: the mis-levelled review node and the node
# without a role must fail, the well-formed review node must pass.
got="$(check_nodes "$fixture" | grep '^FAIL' | sed "s|$fixture:||")"
for want in "FAIL: lowrev (claude review): effort is 'medium', expected 'high'" \
  "FAIL: norole: class '' must carry exactly one role word ($roles)" \
  "FAIL: suffix (claude implement): effort is 'medium-high', expected 'xhigh'" \
  "FAIL: other: ACP node with an unrecognised acp.command"; do
  grep -qxF -- "$want" <<<"$got" || { echo "FAIL: policy self-test lacks: $want; got:" >&2; echo "$got" >&2; exit 1; }
done
grep -q '^FAIL: ok[ :]' <<<"$got" && { echo "FAIL: policy self-test rejected a correct node" >&2; exit 1; }

declare -A seen=()
agents=0
while read -r line; do
  case "$line" in
    "seen "*) seen[${line#seen }]=1; agents=$((agents + 1)) ;;
    *) fail "${line#FAIL: }" ;;
  esac
done < <(check_nodes components/*.fabro .fabro/workflows/*/workflow.fabro)

[[ $agents -gt 0 ]] || fail "no agent nodes found"
for key in "${!override[@]}"; do
  [[ -n "${seen[$key]:-}" ]] || fail "$key: override for a node that does not exist"
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
