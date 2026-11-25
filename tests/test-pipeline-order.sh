#!/usr/bin/env bash
# test-pipeline-order.sh — offline check of the order the verification pipeline runs in.
#
# Policy: a workflow that verifies a diff (small, medium, verify) runs coverage, the Codex
# review, the Claude review, the CodeRabbit review, the security review, the personal-data
# audit, commit and PR, the PR steward and the history rewrite, in that order. The prompts
# that name the reviews addressed before theirs agree with it.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$here"

# The stages, as the names of their components (components/<name>.fabro).
want="coverage codex-review claude-review coderabbit-review security-review personal-data-audit commit-and-pr pr-steward logical-commits"

# pipeline <dot files...>: prints "<file>:<components>" for every file, the components it runs
# from its coverage check on, following the only edge out of each until one leads to a node
# that is not an imported component. Components are told by the file they import, not by the
# name of their placeholder. Nothing after the colon: the file imports neither the coverage
# check nor a review. A "?" marks what is not a pipeline, so that it fails instead of passing:
# reviews without exactly one coverage check, a stage with several edges out, a loop, an edge
# from off the chain into a stage after the coverage check (it skips the stages before), a stage
# imported a second time (the copy off the chain runs out of order), and an edge the scanner
# cannot read (a quoted id, a {group}, a chain continued on the next line).
# shortcut: statements are read line by line, like tests/test-effort-levels.sh; an import
# attribute wrapped onto the line after its node id is not seen.
pipeline() {
  awk '
    # uncomment cuts a // comment off a line (a // inside a quoted string stays).
    function uncomment(s,    i, c, q) {
      for (i = 1; i <= length(s); i++) {
        c = substr(s, i, 1)
        if (q && c == "\\") i++
        else if (c == "\"") q = !q
        else if (!q && c == "/" && substr(s, i + 1, 1) == "/") return substr(s, 1, i - 1)
      }
      return s
    }
    function trim(s) { gsub(/^[[:space:]]+|[[:space:]]+$/, "", s); return s }
    function finish(   id, n, reviews, at, out, m, next_ids, visited, first, src, j, imports, again) {
      n = 0; reviews = 0; again = 0
      for (id in comp) {
        if (comp[id] == "coverage") { at = id; n++ }
        if (comp[id] ~ /-review$/) reviews++
        imports[comp[id]]++
      }
      out = ""
      if (n != 1) { if (n || reviews) out = "?" }
      else {
        first = at
        while (1) {
          out = out (out == "" ? "" : " ") comp[at]
          visited[at] = 1
          if (imports[comp[at]] > 1) again = 1
          m = split(trim(succ[at]), next_ids, " ")
          if (m > 1) { out = out " ?"; break }
          if (m == 0 || !(next_ids[1] in comp)) break
          at = next_ids[1]
          if (at in visited) { out = out " ?"; break }
        }
        # An edge from a node off the chain into a stage after the coverage check skips it.
        for (src in succ) if (!(src in visited)) {
          m = split(trim(succ[src]), next_ids, " ")
          for (j = 1; j <= m; j++) if (next_ids[j] in visited && next_ids[j] != first) entered = 1
        }
        if (unread || entered || again) out = out " ?"
      }
      print file ":" out
      split("", comp); split("", succ); unread = 0; entered = 0
    }
    FNR == 1 { if (file != "") finish(); file = FILENAME }
    {
      line = uncomment($0)
      if (line ~ /^[[:space:]]*[A-Za-z_][A-Za-z0-9_]*[[:space:]]*\[/ && match(line, /import[[:space:]]*=[[:space:]]*"[^"]*"/)) {
        path = substr(line, RSTART, RLENGTH); sub(/^[^"]*"/, "", path); sub(/"$/, "", path)
        sub(/^.*\//, "", path); sub(/\.fabro$/, "", path)
        id = line; sub(/[[:space:]]*\[.*$/, "", id)
        comp[trim(id)] = path
        next
      }
      # Edges, outside quoted strings and without their attribute list.
      gsub(/"([^"\\]|\\.)*"/, "\"\"", line); sub(/\[.*$/, "", line)
      if (line !~ /->/) next
      k = split(line, ids, /->/)
      for (i = 1; i <= k; i++) if (trim(ids[i]) !~ /^[A-Za-z_][A-Za-z0-9_.]*$/) { unread = 1; next }
      for (i = 1; i < k; i++) succ[trim(ids[i])] = succ[trim(ids[i])] " " trim(ids[i + 1])
    }
    END { if (file != "") finish() }
  ' "$@"
}

# Self-test of the scanner on fixtures with the cases it must tell apart.
fix="$(mktemp -d)"; trap 'rm -rf "$fix"' EXIT
fixture() { printf 'digraph T {\n%s\n}\n' "$2" > "$fix/$1.fabro"; }
fixture ok '  a [import="components/coverage.fabro"]
  b [import = "vendor/fidfab/components/codex-review.fabro"]
  c [import="components/claude-review.fabro"]  // c [import="components/coderabbit-review.fabro"]
  gate [shape=hexagon, label="a -> c"]
  start -> gate
  gate -> a [label="go"]
  gate -> done
  a -> b -> c -> done  // a -> c
  done -> exit'
# The order before this check existed: CodeRabbit first.
fixture old '  coverage   [import="components/coverage.fabro"]
  coderabbit [import="components/coderabbit-review.fabro"]
  codex      [import="components/codex-review.fabro"]
  claude     [import="components/claude-review.fabro"]
  coverage -> coderabbit -> codex -> claude -> done'
fixture none '  // coverage [import="components/coverage.fabro"]
  steward [import="components/pr-steward.fabro"]
  "draft" -> steward -> done'
fixture nocoverage '  codex [import="components/codex-review.fabro"]
  start -> codex -> done'
fixture twice '  a [import="components/coverage.fabro"]
  b [import="components/coverage.fabro"]
  a -> b -> done'
fixture fork '  coverage [import="components/coverage.fabro"]
  codex    [import="components/codex-review.fabro"]
  claude   [import="components/claude-review.fabro"]
  coverage -> codex -> claude
  codex -> done [label="skip"]'
fixture loop '  coverage [import="components/coverage.fabro"]
  codex    [import="components/codex-review.fabro"]
  coverage -> codex -> coverage'
fixture quoted '  coverage [import="components/coverage.fabro"]
  codex    [import="components/codex-review.fabro"]
  coverage -> codex -> done
  "coverage" -> done'
fixture grouped '  coverage [import="components/coverage.fabro"]
  codex    [import="components/codex-review.fabro"]
  coverage -> {codex}'
# An entry that skips the coverage check and the Codex review.
fixture entry '  coverage [import="components/coverage.fabro"]
  codex    [import="components/codex-review.fabro"]
  claude   [import="components/claude-review.fabro"]
  start -> coverage -> codex -> claude -> done
  start -> claude [label="skip"]'
# A review imported a second time, ahead of the coverage check.
fixture again '  early    [import="components/claude-review.fabro"]
  coverage [import="components/coverage.fabro"]
  codex    [import="components/codex-review.fabro"]
  claude   [import="components/claude-review.fabro"]
  start -> early -> coverage -> codex -> claude -> done'
fixture wrapped '  coverage [import="components/coverage.fabro"]
  codex    [import="components/codex-review.fabro"]
  claude   [import="components/claude-review.fabro"]
  coverage -> codex ->
    claude -> done'
got="$(cd "$fix" && pipeline ok.fabro old.fabro none.fabro nocoverage.fabro twice.fabro fork.fabro loop.fabro \
  quoted.fabro grouped.fabro entry.fabro again.fabro wrapped.fabro)"
expected="ok.fabro:coverage codex-review claude-review
old.fabro:coverage coderabbit-review codex-review claude-review
none.fabro:
nocoverage.fabro:?
twice.fabro:?
fork.fabro:coverage codex-review ?
loop.fabro:coverage codex-review ?
quoted.fabro:coverage codex-review ?
grouped.fabro:coverage ?
entry.fabro:coverage codex-review claude-review ?
again.fabro:coverage codex-review claude-review ?
wrapped.fabro:coverage ?"
[[ "$got" == "$expected" ]] || { echo "FAIL: scanner self-test; got:" >&2; echo "$got" >&2; exit 1; }

status=0
fail() { echo "FAIL: $*" >&2; status=1; }

# Every workflow with a coverage check or a review runs the whole pipeline in order, and each
# built-in workflow that verifies a diff is one.
workflows=0; seen=""
while IFS= read -r line; do
  file="${line%%:*}"; got="${line#*:}"
  [[ -z "$got" ]] && continue
  workflows=$((workflows + 1)); seen="$seen $file "
  [[ "$got" == "$want" ]] || fail "$file: the pipeline runs: $got; expected: $want"
done < <(pipeline .fabro/workflows/*/workflow.fabro)
for w in small medium verify; do
  [[ "$seen" == *" .fabro/workflows/$w/workflow.fabro "* ]] || fail "$w: the workflow does not run the verification pipeline"
done

# The stage that addresses a review is told which reviews were addressed before it, so that
# it can say when a finding repeats one of theirs: its prompt names the response record of
# every earlier review and of no later one. Stages in pipeline order; the CodeRabbit review
# has two, the fix and the built-in review that stands in for it.
records=(codex-review-response.md claude-review-response.md coderabbit-response.md)
prompts=("address-codex" "address-claude" "coderabbit-review-fix claude-builtin-review")
for i in "${!prompts[@]}"; do
  for p in ${prompts[$i]}; do
    f="components/prompts/$p.md"
    grep -qF -- "${records[$i]}" "$f" || fail "$f: does not name its own record, ${records[$i]}"
    for j in "${!records[@]}"; do
      if ((j < i)); then
        grep -qF -- "${records[$j]}" "$f" || fail "$f: does not name ${records[$j]}, the record of an earlier review"
      elif ((j > i)) && grep -qF -- "${records[$j]}" "$f"; then
        fail "$f: names ${records[$j]}, the record of a later review"
      fi
    done
  done
done

[[ $status -eq 0 ]] && echo "pipeline order: $workflows workflows OK"
exit $status
