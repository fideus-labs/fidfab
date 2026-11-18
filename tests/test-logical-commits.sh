#!/usr/bin/env bash
# test-logical-commits.sh — offline check of the history rewrite stage (logical-commits).
#
# Policy: every workflow that imports the PR steward hands over to the logical-commits
# component and to nothing else, so no pull request keeps its per-stage checkpoint history.
# The stage is Claude opus at medium effort, gets no earlier stage output in its preamble
# (fidelity="truncate"), and its prompt keeps the commands that make the rewrite safe.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$here"

component=components/logical-commits.fabro
prompt=components/prompts/logical-commits.md

# AWK_UNCOMMENT: uncomment cuts a // comment off a line (a // inside a quoted string stays),
# like tests/test-effort-levels.sh.
AWK_UNCOMMENT='
  function uncomment(s,    i, c, q) {
    for (i = 1; i <= length(s); i++) {
      c = substr(s, i, 1)
      if (q && c == "\\") i++
      else if (c == "\"") q = !q
      else if (!q && c == "/" && substr(s, i + 1, 1) == "/") return substr(s, 1, i - 1)
    }
    return s
  }
'

# strip_comments <file>: the file without // comments, for attribute checks on code only.
strip_comments() { awk "$AWK_UNCOMMENT"' { print uncomment($0) }' "$1"; }

# check_wiring <dot files...>: prints "seen <file>" for every file that imports the steward
# and a "FAIL: ..." line for every steward placeholder whose only successor is not a
# logical-commits placeholder, for every logical-commits placeholder that leads nowhere or
# back to a steward, for every statement that names either component but is not an import
# the scanner reads, and for every edge outside quotes it does not read (a quoted node id),
# so a layout it does not understand fails instead of passing.
# feed() reads DOT statements: one ends at ";" or at the end of a line, but not inside a
# quoted string or an attribute list (both carry over to the next line) and not after a
# trailing "->". // comments are dropped.
# shortcut: no /* */ comments, and an edge chain continued by a line that starts with "->"
# loses its link (the check then fails, it does not pass); handle both if a workflow uses them.
check_wiring() {
  awk '
    function trim(s) { gsub(/^[[:space:]]+|[[:space:]]+$/, "", s); return s }
    function feed(s,    i, c) {
      for (i = 1; i <= length(s); i++) {
        c = substr(s, i, 1)
        if (inq) {
          if (c == "\\") { buf = buf c substr(s, i + 1, 1); i++; continue }
          if (c == "\"") inq = 0
        } else if (c == "\"") inq = 1
        else if (c == "/" && substr(s, i + 1, 1) == "/") break
        else if (c == "[") depth++
        else if (c == "]") depth--
        else if (c == ";" && depth <= 0) { flush(); continue }
        buf = buf c
      }
      if (inq || depth > 0 || buf ~ /->[[:space:]]*$/) buf = buf " "
      else flush()
    }
    function flush() { if (buf ~ /[^[:space:]]/) statement(buf); buf = ""; depth = 0; inq = 0 }
    function finish(   s, r, n, next_ids, i) {
      for (s in stewards) {
        print "seen " file
        n = split(trim(succ[s]), next_ids, " ")
        if (n != 1 || !(next_ids[1] in rewrites))
          print "FAIL: " file ": " s " (pr-steward) must lead to logical-commits only, not to: " (n ? trim(succ[s]) : "nothing")
      }
      for (r in rewrites) {
        n = split(trim(succ[r]), next_ids, " ")
        if (!n) print "FAIL: " file ": " r " (logical-commits) leads nowhere"
        for (i = 1; i <= n; i++)
          if (next_ids[i] in stewards) print "FAIL: " file ": " r " (logical-commits) leads back to " next_ids[i]
      }
      split("", stewards); split("", rewrites); split("", succ)
    }
    function statement(st,    path, id, chain, n, ids, i, imported, bare) {
      imported = ""
      if (st ~ /^[[:space:]]*[A-Za-z_][A-Za-z0-9_]*[[:space:]]*\[/ && match(st, /import[[:space:]]*=[[:space:]]*"[^"]*"/)) {
        path = substr(st, RSTART, RLENGTH); sub(/^[^"]*"/, "", path); sub(/"$/, "", path)
        id = st; sub(/[[:space:]]*\[.*$/, "", id); id = trim(id)
        if (path ~ /(^|\/)pr-steward\.fabro$/) { stewards[id] = 1; imported = "pr-steward" }
        if (path ~ /(^|\/)logical-commits\.fabro$/) { rewrites[id] = 1; imported = "logical-commits" }
      } else if (st ~ /^[[:space:]]*[A-Za-z_][A-Za-z0-9_.]*[[:space:]]*->/) {
        chain = st; sub(/[[:space:]]*\[.*$/, "", chain)
        n = split(chain, ids, /[[:space:]]*->[[:space:]]*/)
        for (i = 1; i <= n; i++)
          if (trim(ids[i]) !~ /^[A-Za-z_][A-Za-z0-9_.]*$/) {  # a {group}, "quoted" id or port
            st = trim(st); gsub(/[[:space:]]+/, " ", st); print "FAIL: " file ": an edge the scanner cannot read: " st
            return
          }
        for (i = 1; i < n; i++) succ[trim(ids[i])] = succ[trim(ids[i])] " " trim(ids[i + 1])
      } else {
        bare = st; gsub(/"([^"\\]|\\.)*"/, "", bare)
        if (bare ~ /->/) { st = trim(st); gsub(/[[:space:]]+/, " ", st); print "FAIL: " file ": an edge the scanner cannot read: " st }
      }
      if ((st ~ /pr-steward\.fabro/ && imported != "pr-steward") || (st ~ /logical-commits\.fabro/ && imported != "logical-commits")) {
        st = trim(st); gsub(/[[:space:]]+/, " ", st)
        print "FAIL: " file ": not an import the scanner reads: " st
      }
    }
    FNR == 1 { if (file != "") { flush(); finish() }; file = FILENAME }
    { feed($0) }
    END { if (file != "") { flush(); finish() } }
  ' "$@"
}

# Self-test of the scanner on fixtures with the cases it must tell apart.
fix="$(mktemp -d)"; trap 'rm -rf "$fix"' EXIT
fixture() { printf 'digraph T {\n%s\n}\n' "$2" > "$fix/$1.fabro"; }
fixture ok '  steward [import="components/pr-steward.fabro"]
  history [import = "components/logical-commits.fabro"]
  ship -> steward -> history -> done  // steward -> done
  done -> exit'
fixture missing '  steward [import="components/pr-steward.fabro"]
  ship -> steward -> done'
fixture extra '  steward [import="components/pr-steward.fabro"]
  history [import="components/logical-commits.fabro"]
  steward -> history
  steward -> done [label="skip"]'
fixture before '  steward [import="components/pr-steward.fabro"]
  history [import="components/logical-commits.fabro"]
  ship -> history -> steward -> done'
fixture dangling '  s [import="vendor/fidfab/components/pr-steward.fabro"]
  ship -> s'
fixture none '  // steward [import="components/pr-steward.fabro"]
  ship [import="components/commit-and-pr.fabro"]
  ship -> done'
fixture deadend '  steward [import="components/pr-steward.fabro"]
  history [import="components/logical-commits.fabro"]
  ship -> steward -> history'
fixture oneline '  steward [import="components/pr-steward.fabro"]; history [import="components/logical-commits.fabro"]
  steward -> history [label="a;b"]; steward -> done
  history -> done'
fixture commented '  steward [shape=diamond] // import="components/pr-steward.fabro"
  real [import="components/pr-steward.fabro"]
  history [import="components/logical-commits.fabro"]
  real -> done  // real -> history
  history -> real'
# Node statements wrapped over lines, the layout the workflows use for agent nodes.
fixture wrapped '  steward [label="Steward",
           import="components/pr-steward.fabro"]
  history [label="History";
           import="components/logical-commits.fabro"]
  ship -> steward ->
    history -> done'
fixture wrappedbad '  steward [label="x",
           import="components/pr-steward.fabro"]
  history [import="components/logical-commits.fabro"]
  ship -> steward -> done
  history -> done'
fixture multiline '  steward [label="two
  lines // not a comment", import="components/pr-steward.fabro"]
  history [import="components/logical-commits.fabro"]
  steward -> history -> done'
fixture unread '  steward
    [import="components/pr-steward.fabro"]
  ship -> steward -> done'
fixture quoted '  steward [import="components/pr-steward.fabro"]
  history [import="components/logical-commits.fabro", label="steward -> history"]
  steward -> history -> done
  "steward" -> done'
fixture grouped '  steward [import="components/pr-steward.fabro"]
  history [import="components/logical-commits.fabro"]
  steward -> history -> done
  history -> {steward}'
got="$(cd "$fix" && check_wiring ok.fabro missing.fabro extra.fabro before.fabro dangling.fabro none.fabro \
  deadend.fabro oneline.fabro commented.fabro wrapped.fabro wrappedbad.fabro multiline.fabro unread.fabro \
  quoted.fabro grouped.fabro)"
want="seen ok.fabro
seen missing.fabro
FAIL: missing.fabro: steward (pr-steward) must lead to logical-commits only, not to: done
seen extra.fabro
FAIL: extra.fabro: steward (pr-steward) must lead to logical-commits only, not to: history done
FAIL: extra.fabro: history (logical-commits) leads nowhere
seen before.fabro
FAIL: before.fabro: steward (pr-steward) must lead to logical-commits only, not to: done
FAIL: before.fabro: history (logical-commits) leads back to steward
seen dangling.fabro
FAIL: dangling.fabro: s (pr-steward) must lead to logical-commits only, not to: nothing
seen deadend.fabro
FAIL: deadend.fabro: history (logical-commits) leads nowhere
seen oneline.fabro
FAIL: oneline.fabro: steward (pr-steward) must lead to logical-commits only, not to: history done
seen commented.fabro
FAIL: commented.fabro: real (pr-steward) must lead to logical-commits only, not to: done
FAIL: commented.fabro: history (logical-commits) leads back to real
seen wrapped.fabro
seen wrappedbad.fabro
FAIL: wrappedbad.fabro: steward (pr-steward) must lead to logical-commits only, not to: done
seen multiline.fabro
FAIL: unread.fabro: not an import the scanner reads: [import=\"components/pr-steward.fabro\"]
FAIL: quoted.fabro: an edge the scanner cannot read: \"steward\" -> done
seen quoted.fabro
FAIL: grouped.fabro: an edge the scanner cannot read: history -> {steward}
seen grouped.fabro"
[[ "$got" == "$want" ]] || { echo "FAIL: scanner self-test; got:" >&2; echo "$got" >&2; exit 1; }

status=0
fail() { echo "FAIL: $*" >&2; status=1; }

# Every workflow that stewards a pull request rewrites its history afterwards, and each
# built-in workflow does both.
workflows=0; seen=""
while read -r line; do
  case "$line" in
    "seen "*) workflows=$((workflows + 1)); seen="$seen ${line#seen } " ;;
    *) fail "${line#FAIL: }" ;;
  esac
done < <(check_wiring .fabro/workflows/*/workflow.fabro)
for w in small medium large verify; do
  [[ "$seen" == *" .fabro/workflows/$w/workflow.fabro "* ]] || fail "$w: the workflow does not import the PR steward"
done

# The stage: one agent node, Claude opus at medium effort, no preamble from earlier stages.
# Comments are dropped first (whole lines and trailing ones): the component's header
# describes these attributes.
code="$(strip_comments "$component")"
[[ "$(grep -c 'prompt="' <<<"$code")" == 1 ]] || fail "$component: expected exactly one agent node"
for want in 'acp.command="fidfab-claude-acp --model opus --effort medium"' \
  'fidelity="truncate"' \
  'prompt="@prompts/logical-commits.md"'; do
  grep -qF -- "$want" <<<"$code" || fail "$component: the rewrite node lacks $want"
done
# The rewrite runs only when the steward's last status check said "done" (fidfab-pr-status
# records its label as pr_status; tests/test-pr-steward.sh checks that side). Every other way
# out of the steward (no-pr, an incomplete reply preview) and a missing key take the
# unconditional edge past it.
edges() { grep -E -- "$1" <<<"$code" | sed -E 's/^[[:space:]]+|[[:space:]]+$//g'; }
[[ "$(edges '^[[:space:]]*start[[:space:]]*->')" == 'start -> green' ]] ||
  fail "$component: start must lead to green only, not: $(edges '^[[:space:]]*start[[:space:]]*->')"
[[ "$(edges '->[[:space:]]*record([^A-Za-z0-9_.]|$)')" == 'green -> record [condition="context.pr_status=done"]' ]] ||
  fail "$component: record must be reached only from green on context.pr_status=done, not: $(edges '->[[:space:]]*record([^A-Za-z0-9_.]|$)')"
[[ "$(edges '->[[:space:]]*rewrite([^A-Za-z0-9_.]|$)')" == 'record -> rewrite' ]] ||
  fail "$component: rewrite must be reached only from record, not: $(edges '->[[:space:]]*rewrite([^A-Za-z0-9_.]|$)')"
[[ "$(edges '^[[:space:]]*record[[:space:]]*->' | sort)" == $'record -> done   [condition="outcome=failed"]\nrecord -> rewrite' ]] ||
  fail "$component: record must lead to rewrite, and to done when it fails, not: $(edges '^[[:space:]]*record[[:space:]]*->')"
# The tree check around the agent: record before it, verify after it on every outcome (one
# unconditional edge), and a failed verify stops at the human gate instead of passing.
for want in 'script="fidfab-history-tree record"' 'script="fidfab-history-tree verify"'; do
  grep -qF -- "$want" <<<"$code" || fail "$component: lacks the node $want"
done
[[ "$(edges '^[[:space:]]*rewrite[[:space:]]*->')" == 'rewrite -> verify' ]] ||
  fail "$component: rewrite must lead to verify only, not: $(edges '^[[:space:]]*rewrite[[:space:]]*->')"
[[ "$(edges '^[[:space:]]*verify[[:space:]]*->' | sort)" == $'verify -> alarm  [condition="outcome=failed"]\nverify -> done' ]] ||
  fail "$component: verify must lead to alarm on failure and to done otherwise, not: $(edges '^[[:space:]]*verify[[:space:]]*->')"
grep -qE '^[[:space:]]*alarm[[:space:]]*\[shape=hexagon' <<<"$code" || fail "$component: alarm must be a human gate"
[[ "$(edges '^[[:space:]]*green[[:space:]]*->[[:space:]]*[A-Za-z_]+[[:space:]]*$')" == 'green -> done' ]] ||
  fail "$component: green needs its unconditional edge to done"

# The prompt: the commands that keep the rewrite from changing code or discarding commits.
for want in 'git config merge.conflictstyle diff3' \
  'gh api "repos/{owner}/{repo}/pulls?head={owner}:<branch>&state=open"' \
  'If `gh` exits non-zero' \
  'unless `<prs>` holds exactly one pull request' \
  'git merge-base "origin/<target>" HEAD' \
  'If the fetch fails, change nothing' \
  '`git rev-parse "<remote>^{tree}"` and' \
  'git merge-base --is-ancestor <remote> HEAD' \
  '`<recorded>`, what GitHub had for the branch' \
  '`git merge-base --is-ancestor <recorded> <remote>`' \
  'one of the two lines of' \
  "printf '%s\n' \"<remote>\" \"\$(git rev-parse HEAD)\" > .fidfab/reviews/history-pushed" \
  '`git rev-parse "<before>^{tree}"` and' \
  'outside the work tree (`mktemp -d`)' \
  'git push --force-with-lease="<branch>:<remote>" origin "HEAD:refs/heads/<branch>"' \
  'keep exactly one, `Fabro-Run: <run id>`' \
  '{% include "partials/workspace.md" %}'; do
  grep -qF -- "$want" "$prompt" || fail "$prompt: lacks $want"
done
# Both clean-work-tree checks list untracked files whatever status.showUntrackedFiles says.
[[ "$(grep -c 'git status --porcelain --untracked-files=all' "$prompt")" == 2 &&
  "$(grep -c 'git status --porcelain' "$prompt")" == 2 ]] ||
  fail "$prompt: both work-tree checks must use git status --porcelain --untracked-files=all"
grep -qF 'succeeds and prints nothing' "$prompt" || fail "$prompt: the status check must also succeed"

# The prompt's safety commands behave as it says, on a scratch repository with a bare remote
# standing in for GitHub. Offline: git only.
g() { git -C "$fix/work" -c user.name=t -c user.email=t@example.com -c commit.gpgsign=false "$@"; }
git init -q --bare "$fix/remote.git"
git init -q -b main "$fix/work"
g remote add origin "$fix/remote.git"
echo .fidfab/ >> "$fix/work/.git/info/exclude"  # as fidfab-bootstrap does
g config status.showUntrackedFiles no  # the prompt's status check must not depend on it
porcelain() { g status --porcelain --untracked-files=all; }
g commit -q --allow-empty -m base
g push -q origin main
g checkout -q -b topic
echo a > "$fix/work/a"; g add a; g commit -q -m 'fabro(r): implement (success)'
g commit -q --allow-empty -m 'fabro(r): coverage (success)'
echo b > "$fix/work/b"; g add b; g commit -q -m 'fabro(r): review (success)'
g push -q origin topic
g fetch -q origin
base="$(g merge-base origin/main HEAD)"; remote="$(g rev-parse origin/topic)"; before="$(g rev-parse HEAD)"
same_tree() { [[ "$(g rev-parse "$1^{tree}")" == "$(g rev-parse "$2^{tree}")" ]]; }
lease=(push -q --force-with-lease="topic:$remote" origin HEAD:refs/heads/topic)

g merge-base --is-ancestor "$remote" HEAD || fail "rewrite: is-ancestor rejects an up-to-date checkout"
same_tree "$remote" HEAD || fail "rewrite: the tree check against <remote> rejects an up-to-date checkout"
# An empty checkpoint not pushed yet: the trees still match (Step 1.4 lets it through).
g commit -q --allow-empty -m 'fabro(r): steward.done (success)'
same_tree "$remote" HEAD || fail "rewrite: the tree check against <remote> rejects an unpushed empty checkpoint"
g reset -q --hard "$before"
# A commit with code GitHub never received (an unapproved steward draft): is-ancestor alone
# lets it through, the tree check stops it (Step 1.4).
echo draft > "$fix/work/d"; g add d; g commit -q -m 'Address review comment'
g merge-base --is-ancestor "$remote" HEAD || fail "rewrite: is-ancestor rejects a checkout ahead of GitHub"
same_tree "$remote" HEAD && fail "rewrite: the tree check against <remote> misses unpushed code"
g reset -q --hard "$before"
# Step 2 by soft reset: regroup by file, then the tree must still equal <before>.
g reset -q --soft "$base"
g commit -q -m 'Add a' -- a
g commit -q -m 'Add b'
same_tree "$before" HEAD || fail "rewrite: the tree check against <before> fails after a code-preserving rewrite"
[[ "$(g log --format=%s "$base..HEAD")" == $'Add b\nAdd a' ]] || fail "rewrite: soft-reset regrouping gave $(g log --oneline "$base..HEAD")"
# A rewrite that changes code is caught.
echo changed > "$fix/work/b"; g commit -q -am tweak
same_tree "$before" HEAD && fail "rewrite: the tree check against <before> misses a code change"
g reset -q --hard HEAD~1
# A message file left in the work tree: the tree check passes, but Fabro's checkpoint after
# the stage (add everything, commit) would push it. Only the clean-work-tree check sees it.
echo 'Add b' > "$fix/work/msg"
same_tree "$before" HEAD || fail "rewrite: the tree check against <before> sees the work tree"
[[ -n "$(porcelain)" ]] || fail "rewrite: the status check misses a file left in the work tree"
g add -A; g commit -q -m 'fabro(r): history.rewrite (success)'
same_tree "$before" HEAD && fail "rewrite: the checkpoint after the stage did not pick up the file"
g reset -q --hard HEAD~1
[[ -z "$(porcelain)" ]] || fail "rewrite: the status check is not empty on a clean work tree"
# Step 2 by interactive rebase without an editor: a todo list through GIT_SEQUENCE_EDITOR.
rewritten="$(g rev-parse HEAD)"
g reset -q --hard "$before"
mapfile -t picks < <(g rev-list --reverse "$base..HEAD")
printf 'pick %s\nfixup %s\nfixup %s\n' "${picks[@]}" > "$fix/todo"
TODO="$fix/todo" GIT_SEQUENCE_EDITOR='cp "$TODO"' g rebase -q -i "$base" || fail "rewrite: rebase with GIT_SEQUENCE_EDITOR failed"
[[ "$(g rev-list --count "$base..HEAD")" == 1 ]] || fail "rewrite: scripted rebase did not squash to one commit"
same_tree "$before" HEAD || fail "rewrite: scripted squash changed the tree"
g reset -q --hard "$rewritten"

# Someone pushed to GitHub meanwhile: the lease rejects the force-push and keeps their commit.
git clone -q -b topic "$fix/remote.git" "$fix/other"
echo theirs > "$fix/other/c"; git -C "$fix/other" add c
git -C "$fix/other" -c user.name=o -c user.email=o@example.com -c commit.gpgsign=false \
  commit -q -m theirs
git -C "$fix/other" push -q origin HEAD:refs/heads/topic
theirs="$(git -C "$fix/other" rev-parse HEAD)"
g "${lease[@]}" 2>/dev/null && fail "rewrite: --force-with-lease overwrote a commit pushed meanwhile"
[[ "$(git -C "$fix/remote.git" rev-parse topic)" == "$theirs" ]] || fail "rewrite: the commit pushed meanwhile was lost"
g fetch -q origin
g merge-base --is-ancestor origin/topic HEAD && fail "rewrite: is-ancestor misses a commit pushed meanwhile"
same_tree origin/topic HEAD && fail "rewrite: a foreign commit looks like an earlier rewrite"
# Step 1.5: who moved GitHub since the record node saw <recorded>. Fabro's checkpoints and
# this stage's own recorded attempts pass; a push, rewording or rewind by someone else stops it.
recorded="$remote"
pushed="$fix/work/.fidfab/reviews/history-pushed"
may_continue() {
  local r; r="$(g rev-parse origin/topic)"
  { g merge-base --is-ancestor "$recorded" "$r" && g merge-base --is-ancestor "$r" HEAD; } ||
    grep -qxF "$r" "$pushed" 2>/dev/null
}
git -C "$fix/remote.git" update-ref refs/heads/topic "$remote"
g fetch -q --force origin
g reset -q --hard "$before"
may_continue || fail "rewrite: step 1.5 rejects GitHub as recorded"
g commit -q --allow-empty -m 'fabro(r): history.record (success)'
g push -q origin topic; g fetch -q origin
may_continue || fail "rewrite: step 1.5 rejects a Fabro checkpoint pushed after the record"
# Someone rewinds GitHub to a same-tree ancestor of the recorded head.
recorded="$(g rev-parse HEAD)"
git -C "$fix/remote.git" update-ref refs/heads/topic "$remote"; g fetch -q --force origin
{ same_tree origin/topic HEAD && g merge-base --is-ancestor origin/topic HEAD; } || fail "rewrite: the rewind is not a same-tree ancestor"
may_continue && fail "rewrite: step 1.5 accepts a rewind behind the recorded head"
recorded="$remote"
# An attempt records the lease and its candidate (Step 3.3) and stops before pushing: the
# retry starts from the candidate, and GitHub still holds what the attempt found.
g reset -q --hard "$rewritten"
may_continue && fail "rewrite: step 1.5 accepts a rewritten checkout without a record"
mkdir -p "$(dirname "$pushed")"; printf '%s\n' "$remote" "$(g rev-parse HEAD)" > "$pushed"
may_continue || fail "rewrite: step 1.5 rejects a retry whose earlier attempt never pushed"
# The push: the lease on the examined commit lets the rewrite through.
g "${lease[@]}" || fail "rewrite: --force-with-lease rejected the expected remote"
[[ "$(git -C "$fix/remote.git" rev-parse topic)" == "$(g rev-parse HEAD)" ]] || fail "rewrite: GitHub does not hold the rewrite"
[[ -z "$(porcelain)" ]] || fail "rewrite: the history-pushed record shows up in the work tree"
# Retry after the earlier attempt pushed, from the checkout before it: not an ancestor, the
# same tree, and recorded.
g reset -q --hard "$before"
g fetch -q origin
g merge-base --is-ancestor origin/topic HEAD && fail "rewrite: is-ancestor accepts a pushed rewrite as ancestor"
same_tree origin/topic HEAD || fail "rewrite: an earlier pushed rewrite does not have the tree"
may_continue || fail "rewrite: step 1.5 rejects the rewrite an earlier attempt pushed"
# Someone rewords the branch on GitHub: same tree, not an ancestor, not recorded.
git -C "$fix/other" fetch -q origin; git -C "$fix/other" reset -q --hard origin/topic
git -C "$fix/other" -c user.name=o -c user.email=o@example.com -c commit.gpgsign=false \
  commit -q --amend -m reworded
git -C "$fix/other" push -q --force origin HEAD:refs/heads/topic
g fetch -q origin
same_tree origin/topic HEAD || fail "rewrite: the reworded branch should keep the tree"
may_continue && fail "rewrite: step 1.5 accepts a foreign rewording of the branch"

# fidfab-history-tree on the same repository: a code-preserving rewrite passes, changed code
# on either side fails.
ht="$here/docker/rootfs/usr/local/bin/fidfab-history-tree"
h() { (cd "$fix/work" && "$ht" "$@"); }
g checkout -q -B topic "$before"; g push -q --force origin topic
h verify >/dev/null 2>&1 && fail "history-tree: verify passes without a recorded tree"
h record >/dev/null || fail "history-tree: record failed"
[[ "$(cat "$fix/work/.fidfab/reviews/history-tree")" == "$(g rev-parse "HEAD^{tree}")"$'\ntopic\n'"$(g rev-parse origin/topic)" ]] || fail "history-tree: recorded the wrong tree, branch or GitHub commit"
g reset -q --soft "$base"; g commit -q -m 'Add a and b'; g push -q --force origin topic
h verify >/dev/null || fail "history-tree: verify rejects a code-preserving rewrite"
echo changed > "$fix/work/b"; g commit -q -am tweak
h verify >/dev/null 2>&1 && fail "history-tree: verify misses changed code in HEAD"
g push -q origin topic; g reset -q --hard HEAD~1
h verify >/dev/null 2>&1 && fail "history-tree: verify misses changed code on GitHub"
g push -q --force origin topic
h verify >/dev/null || fail "history-tree: verify rejects the branch put back"
g checkout -q -b elsewhere
h verify >/dev/null 2>&1 && fail "history-tree: verify passes on a branch other than the recorded one"
g checkout -q topic
g push -q origin --delete topic
h verify >/dev/null 2>&1 && fail "history-tree: verify passes when the pushed branch disappeared"
h record >/dev/null || fail "history-tree: record failed on a branch not on GitHub"
[[ "$(sed -n 3p "$fix/work/.fidfab/reviews/history-tree")" == unpublished ]] || fail "history-tree: a branch not on GitHub is not recorded as unpublished"
h verify >/dev/null || fail "history-tree: verify rejects a branch not on GitHub at record time"
g rev-parse "HEAD^{tree}" > "$fix/work/.fidfab/reviews/history-tree"
h verify >/dev/null 2>&1 && fail "history-tree: verify accepts a record without branch and remote"
rc=0; h bogus >/dev/null 2>&1 || rc=$?; [[ $rc -eq 2 ]] || fail "history-tree: unknown command not rejected with 2"

[[ $status -eq 0 ]] && echo "logical commits: $workflows workflows OK"
exit $status
