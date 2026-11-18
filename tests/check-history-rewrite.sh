#!/usr/bin/env bash
# check-history-rewrite.sh — the history rewrite is the stage after the PR steward in every
# workflow, and Fabro does not push the run branch itself.
#
# For every .fabro/workflows/<name>/:
#   - a workflow that imports components/pr-steward.fabro also imports
#     components/rewrite-history.fabro; that node is the steward's only successor and has
#     no other predecessor, so the rewrite runs after the steward and not on a path that
#     opened no pull request;
#   - a workflow that imports the rewrite sets `[run.run_branch] push = false` in
#     workflow.toml. Otherwise Fabro pushes its checkpoint commits, the ones made after the
#     rewrite included, on top of the rewritten history.
# The component's one agent node is Claude opus at medium effort with fidelity="truncate"
# (earlier stage output, such as review-thread listings, stays out of its preamble), is
# entered only through the "done" edge of a script node that runs fidfab-pr-status (the
# steward also ends with no pull request and after a failed reply preview; the rewrite
# runs only once the pull request is green and quiet), and does not push: its only
# successor is a script node running fidfab-rewrite-push, which pushes only an unchanged
# tree and is entered from nowhere else, and its prompt has no forced `git push`.
# Offline; no fabro needed.
#
# Usage: tests/check-history-rewrite.sh [repo-root]   (default: this repository)
set -euo pipefail
root="$(cd "${1:-$(dirname "${BASH_SOURCE[0]}")/..}" && pwd)"
cd "$root"

steward=components/pr-steward.fabro
rewrite=components/rewrite-history.fabro

# Shared by the two scanners: code() cuts a // comment off a line (a // inside a quoted
# string stays) and drops the optional spaces around "=", the spelling DOT allows;
# unquoted() removes the quoted strings, which may contain "]" or "->".
# shortcut: quote state starts fresh on every line, so a string continued over several
# lines is not tracked; carry the state across lines if a statement ever needs one.
awk_code='
  function code(s,    i, c, q) {
    for (i = 1; i <= length(s); i++) {
      c = substr(s, i, 1)
      if (q && c == "\\") i++
      else if (c == "\"") q = !q
      else if (!q && c == "/" && substr(s, i + 1, 1) == "/") { s = substr(s, 1, i - 1); break }
    }
    gsub(/[[:space:]]*=[[:space:]]*"/, "=\"", s)
    return s
  }
  function unquoted(s,    i, c, q, out) {
    for (i = 1; i <= length(s); i++) {
      c = substr(s, i, 1)
      if (q && c == "\\") i++
      else if (c == "\"") q = !q
      else if (!q) out = out c
    }
    return out
  }'

# nodes <dot file>: one line per node statement, "<name> <its attribute list on one line>".
nodes() {
  awk "$awk_code"'
    function flush() { if (node != "") print node, text; node = ""; text = "" }
    { $0 = code($0) }
    /^[[:space:]]*[A-Za-z_][A-Za-z0-9_]*[[:space:]]*->/ { flush(); next }
    /^[[:space:]]*[A-Za-z_][A-Za-z0-9_]*[[:space:]]*\[/ {
      flush()
      name = $0; sub(/^[[:space:]]*/, "", name); sub(/[[:space:]]*\[.*$/, "", name)
      if (name != "graph" && name != "node" && name != "edge") node = name
    }
    node != "" { text = text " " $0 }
    END { flush() }
  ' "$1"
}

# edges <dot file>: "<from> <to>" for every edge; a chain a -> b -> c gives two.
# shortcut: an edge statement is read from one line.
edges() {
  awk "$awk_code"'
    { $0 = unquoted(code($0)) }
    /->/ {
      gsub(/\[[^]]*\]/, "")
      n = split($0, part, /->/)
      for (i = 1; i <= n; i++) gsub(/[[:space:];]/, "", part[i])
      for (i = 1; i < n; i++) print part[i], part[i + 1]
    }
  ' "$1"
}

# edge_labels <dot file> <from> <to>: "label=<its label>" for every edge statement
# "<from> -> <to> [...]", one line each ("label=" for an edge without one, a line that
# command substitution does not drop).
# shortcut: an edge in a chain (a -> b -> c) is not matched, so a lint that needs every edge
# into a node to carry a label fails on a chain rather than passing it.
edge_labels() {
  awk -v from="$2" -v to="$3" "$awk_code"'
    { s = code($0); u = unquoted(s) }
    u ~ /->/ {
      gsub(/\[[^]]*\]/, "", u)
      if (split(u, part, /->/) != 2) next
      for (i = 1; i <= 2; i++) gsub(/[[:space:];]/, "", part[i])
      if (part[1] != from || part[2] != to) next
      label = ""
      if (match(s, /[[:space:],[]label="[^"]*"/)) {
        label = substr(s, RSTART + 1, RLENGTH - 1); sub(/^label="/, "", label); sub(/"$/, "", label)
      }
      print "label=" label
    }
  ' "$1"
}

# imports <dot file> <component>: the nodes that import it, one per line.
imports() { nodes "$1" | awk -v want="import=\"$2\"" 'index($0, want) { print $1 }'; }

# run_branch_push <workflow.toml>: the value of push in the [run.run_branch] table.
# shortcut: only the table form is read, not `run.run_branch.push = ...` or an inline table.
run_branch_push() {
  awk '
    { sub(/#.*/, ""); gsub(/[[:space:]]/, "") }
    /^\[/ { in_table = ($0 == "[run.run_branch]"); next }
    in_table && /^push=/ { sub(/^push=/, ""); print }
  ' "$1"
}

status=0
fail() { echo "$1: $2"; status=1; }

seen_rewrite=0
for wf in .fabro/workflows/*/workflow.fabro; do
  [[ -f "$wf" ]] || continue
  toml="${wf%.fabro}.toml"
  stewards="$(imports "$wf" "$steward")"
  rewrites="$(imports "$wf" "$rewrite")"
  graph="$(edges "$wf")"

  for s in $stewards; do
    next="$(awk -v n="$s" '$1 == n { print $2 }' <<<"$graph" | sort -u)"
    if [[ "$(grep -c . <<<"$next")" != 1 ]] || ! grep -qxF -- "$next" <<<"$rewrites"; then
      fail "$wf" "the steward '$s' must be followed by the $rewrite import and nothing else (followed by: $(echo ${next:-nothing}))"
    fi
  done
  for r in $rewrites; do
    seen_rewrite=1
    prev="$(awk -v n="$r" '$2 == n { print $1 }' <<<"$graph" | sort -u)"
    [[ -n "$prev" ]] || fail "$wf" "'$r' ($rewrite) is not reached by any edge"
    for p in $prev; do
      grep -qxF -- "$p" <<<"$stewards" \
        || fail "$wf" "'$r' ($rewrite) must be entered from the PR steward only, not from '$p'"
    done
  done
  if [[ -n "$rewrites" ]]; then
    push="$([[ -f "$toml" ]] && run_branch_push "$toml" || true)"
    [[ "$push" == false ]] \
      || fail "$toml" "[run.run_branch] push is '${push:-unset}', expected false: Fabro would push its checkpoint commits over the rewritten history"
  fi
done

if [[ -f "$rewrite" ]]; then
  agents="$(nodes "$rewrite" | grep -E '(^|[[:space:],[])prompt="' || true)"
  if [[ "$(grep -c . <<<"$agents")" != 1 ]]; then
    fail "$rewrite" "expected exactly one agent node"
  else
    node="${agents%% *}"
    [[ "$agents" == *'backend="acp"'* && "$agents" == *'acp.command="fidfab-claude-acp --model opus --effort medium"'* ]] \
      || fail "$rewrite" "'$node' must run 'fidfab-claude-acp --model opus --effort medium' over ACP"
    [[ "$agents" == *'fidelity="truncate"'* ]] \
      || fail "$rewrite" "'$node' must set fidelity=\"truncate\": the default preamble carries earlier stage output"
    # The steward also ends with no pull request and after a failed reply preview, threads
    # still awaiting replies; fidfab-pr-status says "done" only when the PR is green and quiet.
    prev="$(edges "$rewrite" | awk -v n="$node" '$2 == n { print $1 }' | sort -u)"
    [[ -n "$prev" ]] || fail "$rewrite" "'$node' is not reached by any edge"
    for p in $prev; do
      gate="$(nodes "$rewrite" | awk -v n="$p" '$1 == n')"
      labels="$(edge_labels "$rewrite" "$p" "$node")"
      if [[ "$gate" != *'script="'*fidfab-pr-status* || -z "$labels" ]] || grep -qvx label=done <<<"$labels"; then
        fail "$rewrite" "'$node' must be entered only through the \"done\" edge of a script node running fidfab-pr-status, not from '$p'"
      fi
    done
    # The agent reads text written by run agents and anyone with push access; the push is
    # left to fidfab-rewrite-push, which refuses unless the tree is the pull request's.
    next="$(edges "$rewrite" | awk -v n="$node" '$1 == n { print $2 }' | sort -u)"
    pusher="$(nodes "$rewrite" | awk -v n="$next" '$1 == n')"
    if [[ "$(grep -c . <<<"$next")" != 1 || "$pusher" != *'script="'*fidfab-rewrite-push* ]]; then
      fail "$rewrite" "'$node' must be followed by a script node running fidfab-rewrite-push and nothing else (followed by: $(echo ${next:-nothing}))"
    else
      for p in $(edges "$rewrite" | awk -v n="$next" '$2 == n { print $1 }' | sort -u); do
        [[ "$p" == "$node" ]] || fail "$rewrite" "'$next' (fidfab-rewrite-push) must be entered from '$node' only, not from '$p'"
      done
    fi
    prompt="$(sed -nE 's/.*[[:space:],[]prompt="@([^"]*)".*/\1/p' <<<"$agents")"
    if [[ -z "$prompt" || ! -f "components/$prompt" ]]; then
      fail "$rewrite" "'$node' needs a prompt file under components/ (prompt=\"@${prompt:-...}\")"
    else
      # The agent must leave the push to fidfab-rewrite-push, not force-push itself.
      if grep -nE -- 'git push( [^ `]+)* (-f|--force[a-z-]*)([ `.,;:)=]|$)' "components/$prompt"; then
        fail "components/$prompt" "must not force-push; fidfab-rewrite-push pushes after it"
      fi
    fi
  fi
elif [[ $seen_rewrite -eq 1 ]]; then
  fail "$rewrite" "imported by a workflow but missing"
fi
exit $status
