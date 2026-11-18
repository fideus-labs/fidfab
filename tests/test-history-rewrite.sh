#!/usr/bin/env bash
# test-history-rewrite.sh — host-side check of the history rewrite lint
# (tests/check-history-rewrite.sh): against scratch repositories that break one rule each,
# and against this repository's workflows.
set -euo pipefail
cd "$(dirname "$0")/.."
repo="$PWD"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT

# scratch <dir>: a minimal repository that satisfies the lint.
scratch() {
  mkdir -p "$1/components/prompts" "$1/.fabro/workflows/w"
  cat > "$1/components/rewrite-history.fabro" <<'DOT'
digraph RewriteHistory {
  start [shape=Mdiamond]
  exit  [shape=Msquare]
  rewrite [label="Rewrite history", class="claude opus git",
           backend="acp", acp.command="fidfab-claude-acp --model opus --effort medium",
           prompt="@prompts/rewrite-history.md", fidelity="truncate"]
  done [shape=diamond]
  start -> rewrite -> done -> exit
}
DOT
  echo 'Push with `git push --force-with-lease --force-if-includes`, never with a plain `--force`.' \
    > "$1/components/prompts/rewrite-history.md"
  cat > "$1/.fabro/workflows/w/workflow.fabro" <<'DOT'
digraph W {
  start [shape=Mdiamond]
  exit  [shape=Msquare]
  has_changes [script="true", output_schema="routing"]
  ship    [import="components/commit-and-pr.fabro"]
  steward [import="components/pr-steward.fabro"]
  history [import="components/rewrite-history.fabro"]
  done    [shape=diamond, label="Done"]
  start -> has_changes
  has_changes -> ship [label="has-changes"]
  has_changes -> done [label="no-changes"]
  ship -> steward -> history -> done
  done -> exit
}
DOT
  printf '[run.clone]\nenabled = true\n\n[run.run_branch]\npush = false\n' \
    > "$1/.fabro/workflows/w/workflow.toml"
}

fail=0; n=0
# check NAME pass                      the scratch repository after EDIT passes the lint
# check NAME fail MESSAGE              ... fails it, with MESSAGE in the output
# EDIT is read from stdin: shell commands run in the scratch repository, with $wf, $toml,
# $comp and $prompt naming its four files.
check() {
  local name="$1" want="$2" message="${3:-}" r="$tmp/r$((n += 1))" rc=0 edit
  edit="$(cat)"
  scratch "$r"; scratch "$r.orig"
  ( cd "$r" && wf=.fabro/workflows/w/workflow.fabro toml=.fabro/workflows/w/workflow.toml \
      comp=components/rewrite-history.fabro prompt=components/prompts/rewrite-history.md \
      bash -euc "$edit" )
  # An edit that no longer matches the scratch files would test nothing.
  if [[ "$edit" != ":" ]] && diff -r -q "$r.orig" "$r" >/dev/null; then
    echo "FAIL $name: the edit changed nothing"; fail=1; return
  fi
  "$repo/tests/check-history-rewrite.sh" "$r" >"$tmp/log" 2>&1 || rc=$?
  if [[ $want == pass && $rc -eq 0 ]] || { [[ $want == fail && $rc -ne 0 ]] && grep -qF -- "$message" "$tmp/log"; }; then
    echo "ok   $name"
  else
    echo "FAIL $name: want $want${message:+ with '$message'}, exit $rc"; cat "$tmp/log"; fail=1
  fi
}

check "minimal repository" pass <<<':'
check "spaces around = and a label with ] and ->" pass <<'EDIT'
sed -i 's|ship -> steward -> history -> done|ship -> steward\n  steward -> history [ label = "[R] a -> b" ]\n  history -> done|' $wf
sed -i 's|import="components/rewrite-history.fabro"|import = "components/rewrite-history.fabro"|' $wf
EDIT
check "workflow without a steward" pass <<'EDIT'
sed -i '/pr-steward\|rewrite-history/d; s|ship -> steward -> history -> done|ship -> done|' $wf
printf '[run.clone]\nenabled = true\n' > $toml
EDIT
check "comment after the setting" pass <<<'sed -i "s|^push = false|push = false  # see README|" $toml'

check "push = true" fail "push is 'true'" <<<'sed -i "s|^push = false|push = true|" $toml'
check "no [run.run_branch] table" fail "push is 'unset'" <<<'printf "[run.clone]\nenabled = true\n" > $toml'
check "push = false only in a comment" fail "push is 'unset'" <<<'sed -i "s|^push = false|# push = false|" $toml'
check "push = false in another table" fail "push is 'unset'" <<<'printf "[run.run_branch]\nenabled = true\n\n[run.other]\npush = false\n" > $toml'
check "no workflow.toml" fail "push is 'unset'" <<<'rm $toml'

check "steward goes straight to done" fail "the steward 'steward' must be followed" <<'EDIT'
sed -i '/rewrite-history/d; s|ship -> steward -> history -> done|ship -> steward -> done|' $wf
EDIT
check "rewrite imported but not wired" fail "the steward 'steward' must be followed" <<'EDIT'
sed -i 's|ship -> steward -> history -> done|ship -> steward -> done|' $wf
EDIT
check "... and reported as unreachable" fail "'history' (components/rewrite-history.fabro) is not reached" <<'EDIT'
sed -i 's|ship -> steward -> history -> done|ship -> steward -> done|' $wf
EDIT
check "edge to the rewrite only in a comment" fail "the steward 'steward' must be followed" <<'EDIT'
sed -i 's|ship -> steward -> history -> done|ship -> steward -> done  // steward -> history|' $wf
EDIT
check "steward has a second successor" fail "followed by: done history" <<'EDIT'
sed -i 's|^  done -> exit|  steward -> done [condition="outcome=failed"]\n&|' $wf
EDIT
check "rewrite also on the no-changes path" fail "not from 'has_changes'" <<'EDIT'
sed -i 's|has_changes -> done \[label="no-changes"\]|has_changes -> history [label="no-changes"]|' $wf
EDIT
check "rewrite before the steward" fail "not from 'ship'" <<'EDIT'
sed -i 's|ship -> steward -> history -> done|ship -> history -> steward -> done|' $wf
EDIT

check "fable instead of opus" fail "must run 'fidfab-claude-acp --model opus --effort medium'" <<<'sed -i "s|--model opus|--model fable|" $comp'
check "high effort" fail "must run 'fidfab-claude-acp --model opus --effort medium'" <<<'sed -i "s|--effort medium|--effort high|" $comp'
check "Codex instead of Claude" fail "must run 'fidfab-claude-acp --model opus --effort medium'" <<<'sed -i "s|fidfab-claude-acp --model opus|fidfab-codex-acp --model terra|" $comp'
check "default fidelity" fail 'must set fidelity="truncate"' <<<'sed -i "s|, fidelity=\"truncate\"||" $comp'
check "fidelity only in a comment" fail 'must set fidelity="truncate"' <<<'sed -i "s|, fidelity=\"truncate\"\]|]  // fidelity=\"truncate\"|" $comp'
check "two agent nodes" fail "expected exactly one agent node" <<<'sed -i "s|^  done \[shape=diamond\]|  extra [backend=\"acp\", acp.command=\"fidfab-claude-acp --model opus --effort medium\", prompt=\"@prompts/rewrite-history.md\"]\n&|" $comp'
check "component missing" fail "imported by a workflow but missing" <<<'rm $comp'
check "prompt file missing" fail "needs a prompt file" <<<'rm $prompt'
check "prompt without a lease" fail "must push with 'git push --force-with-lease --force-if-includes'" <<<'echo "Push with git push." > $prompt'
check "prompt with a lease alone" fail "must push with 'git push --force-with-lease --force-if-includes'" <<<'sed -i "s| --force-if-includes||" $prompt'
check "prompt with a plain --force" fail "must not push with a plain --force" <<<'echo "Or run \`git push --force\`." >> $prompt'
check "prompt with push -f to a remote" fail "must not push with a plain --force" <<<'echo "Or run git push origin HEAD -f" >> $prompt'

if "$repo/tests/check-history-rewrite.sh"; then echo "ok   repository workflows"
else echo "FAIL repository workflows"; fail=1; fi
# Every workflow in this repository has a steward, so each one must carry the rewrite.
for wf in .fabro/workflows/*/workflow.fabro; do
  if grep -q 'import="components/rewrite-history.fabro"' "$wf"; then echo "ok   $wf imports the rewrite"
  else echo "FAIL $wf does not import components/rewrite-history.fabro"; fail=1; fi
done
exit $fail
