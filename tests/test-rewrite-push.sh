#!/usr/bin/env bash
# test-rewrite-push.sh — host-side check of fidfab-rewrite-push against scratch repositories
# with a bare origin: it pushes a rewritten history only when its tree is the pull request's
# tree, its merge base with the base branch is the pull request's, it has no merge commits
# and no checkpoint metadata is left; it leaves out the empty checkpoint Fabro adds after the
# agent's stage, refuses everything else without touching origin, and does not overwrite a
# push made after the rewrite started. A fake gh stands in for GitHub where a case needs it.
set -euo pipefail
cd "$(dirname "$0")/.."
bin="$PWD/docker/rootfs/usr/local/bin"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.com \
  GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.com \
  GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export PATH="$bin:$PATH"
# Without a token the helper takes the base from .fidfab/run.env or main; cases that need
# GitHub set GH_TOKEN and a fake gh (below) answering with $FAKE_PR.
unset GH_TOKEN GITHUB_TOKEN
mkdir "$tmp/fakebin"
cat > "$tmp/fakebin/gh" <<'GH'
#!/usr/bin/env bash
[[ -n "${FAKE_PR:-}" ]] || exit 1
printf '%s\n' "$FAKE_PR"
GH
chmod +x "$tmp/fakebin/gh"

fail=0; n=0
# setup <dir>: origin (bare) with main and a pull request branch "topic" of a feature commit
# and two checkpoint commits, and main one commit ahead of the branch's base (it advanced
# after the pull request was opened); <dir>/work tracks origin/topic and has the same three
# commits squashed into one on the same base, the tree unchanged.
setup() {
  local d="$1"
  git init -q --bare -b main "$d/origin.git"
  git init -q -b main "$d/seed"
  (
    cd "$d/seed"
    echo zero > z; git add z; git commit -qm zero
    echo base > a; git add a; git commit -qm base
    git remote add origin "$d/origin.git"; git push -q origin main
    git checkout -q -b topic
    echo feature >> a; git commit -qam "Add the feature"
    echo test > t; git add t; git commit -qm "fabro(01RUN): implement (success)"
    git commit -q --allow-empty -m "fabro(01RUN): verify (success)"
    git push -q origin topic
    git checkout -q main; echo later > m; git add m; git commit -qm "Later on main"
    git push -q origin main
  )
  git clone -q -b topic "$d/origin.git" "$d/work"
  (
    cd "$d/work"
    git reset -q --soft origin/main~1
    git commit -qm "Add the feature with its test" -m "Why it is needed."
    # fidfab-bootstrap records the run branch; .fidfab is git-ignored in a real workspace.
    mkdir .fidfab; printf 'FIDFAB_BRANCH=topic\n' > .fidfab/run.env; echo .fidfab > .git/info/exclude
  )
}

# check NAME pass|fail MESSAGE <<< EDIT: run EDIT in a fresh work clone, then the helper.
# pass: it exits 0 and origin/topic is the clone's HEAD (or unchanged with nothing to push);
# fail: it exits non-zero with MESSAGE and origin/topic is what it was before.
check() {
  local name="$1" want="$2" message="${3:-}" d="$tmp/r$((n += 1))" rc=0 edit before after head
  edit="$(cat)"
  setup "$d"
  ( cd "$d/work" && ORIGIN="$d/origin.git" bash -euc "$edit" )
  before="$(git -C "$d/origin.git" rev-parse topic)"
  ( cd "$d/work" && PATH="$tmp/fakebin:$PATH" fidfab-rewrite-push ) >"$tmp/log" 2>&1 || rc=$?
  after="$(git -C "$d/origin.git" rev-parse topic)"
  head="$(git -C "$d/work" rev-parse HEAD 2>/dev/null || true)"
  # Fabro's empty checkpoint after the agent's stage is not pushed.
  if git -C "$d/work" log -1 --format=%s 2>/dev/null | grep -q '^fabro(01RUN): history.rewrite'; then
    head="$(git -C "$d/work" rev-parse HEAD^)"
  fi
  local ok=0
  if [[ $want == pass ]]; then [[ $rc -eq 0 && "$after" == "$head" ]] && ok=1
  else [[ $rc -ne 0 && "$after" == "$before" ]] && ok=1; fi
  if [[ $ok -eq 1 ]] && grep -qF -- "$message" "$tmp/log"; then
    echo "ok   $name"
  else
    echo "FAIL $name: want $want${message:+ with '$message'}, exit $rc, origin/topic $before -> $after, HEAD $head"
    cat "$tmp/log"; fail=1
  fi
}

check "rewritten history with the same tree" pass "pushed 1 rewritten commit(s) to origin/topic" <<<':'
check "nothing rewritten" pass "nothing to push" <<<'git reset -q --hard "@{u}"'
check "same tree, several commits" pass "pushed 2 rewritten commit(s)" <<'EDIT'
git reset -q --soft origin/main~1
git reset -q t; git commit -qm "Add the feature to a"; git add t; git commit -qm "Test the feature"
EDIT

check "content changed" fail "differs from the tree of origin/topic" <<<'echo extra >> a; git commit -qam "Add the feature with its test and more"'
check "someone pushed after the rewrite started" fail "differs from the tree of origin/topic" <<'EDIT'
git clone -q -b topic "$ORIGIN" ../other
( cd ../other && echo theirs > b && git add b && git commit -qm "Their fix" && git push -q origin topic )
EDIT
check "checkpoint subject left" fail "Fabro checkpoint subjects or metadata" <<<'git commit -q --amend -m "fabro(01RUN): rewrite (success)"'
check "checkpoint trailer left" fail "Fabro checkpoint subjects or metadata" <<<'git commit -q --amend -m "Add the feature" -m "Fabro-Run: 01RUN"'
check "Fabro co-author left" fail "Fabro checkpoint subjects or metadata" <<<'git commit -q --amend -m "Add the feature" -m "Co-Authored-By: Fabro <noreply@fabro.sh>"'
check "uncommitted changes" fail "uncommitted changes" <<<'echo dirty >> a'
check "untracked file" fail "uncommitted changes" <<<'echo new > u'
check "untracked file, status.showUntrackedFiles=no" fail "uncommitted changes" <<<'git config status.showUntrackedFiles no; echo new > u'
check "detached HEAD" fail "HEAD is detached" <<<'git checkout -q --detach'
check "rebase in progress" fail "rebase, merge or cherry-pick is in progress" <<<'mkdir .git/rebase-merge'
check "no upstream" fail "has no upstream" <<<'git branch -q --unset-upstream'
check "upstream on another remote" fail "expected 'origin/topic'" <<'EDIT'
git remote add fork "$ORIGIN"; git fetch -q fork; git branch -q -u fork/topic
EDIT
check "upstream is another branch" fail "expected 'origin/topic'" <<'EDIT'
git fetch -q origin main; git branch -q -u origin/main
EDIT
# Fabro commits a checkpoint after the agent's stage, an empty one if it left nothing.
check "empty checkpoint after the rewrite" pass "pushed 1 rewritten commit(s)" <<'EDIT'
git commit -q --allow-empty -m "fabro(01RUN): history.rewrite (success)" -m "Fabro-Run: 01RUN"
EDIT
check "went back, then the checkpoint" pass "nothing to push" <<'EDIT'
git reset -q --hard "@{u}"; git commit -q --allow-empty -m "fabro(01RUN): history.rewrite (success)"
EDIT
check "checkpoint holding changes after the rewrite" fail "differs from the tree of origin/topic" <<'EDIT'
echo left >> a; git commit -qam "fabro(01RUN): history.rewrite (success)"
EDIT
check "back to an empty checkpoint of the pull request" fail "behind origin/topic" <<<'git reset -q --hard "@{u}~1"'
check "only the last commits rewritten" fail "Fabro checkpoint subjects or metadata" <<'EDIT'
git reset -q --hard "@{u}~1"; git commit -q --allow-empty -m "Finish the feature"
EDIT
check "lower-case Fabro co-author left" fail "Fabro checkpoint subjects or metadata" <<<'git commit -q --amend -m "Add the feature" -m "Co-authored-by: Fabro <noreply@fabro.sh>"'
check "moved onto the newer base, same tree" fail "is based on" <<'EDIT'
git reset -q --soft origin/main; git commit -qm "Add the feature with its test"
EDIT
check "parented below the base" fail "is based on" <<'EDIT'
c="$(git commit-tree "HEAD^{tree}" -p origin/main~2 -m "Add the base and the feature")"; git reset -q --hard "$c"
EDIT
check "root commit with the same tree" fail "no merge base" <<'EDIT'
c="$(git commit-tree "HEAD^{tree}" -m "Everything")"; git reset -q --hard "$c"
EDIT
check "merge commit bringing in other history" fail "merge commits" <<'EDIT'
side="$(git commit-tree "origin/main~1^{tree}" -p origin/main~1 -m "Unreviewed")"
c="$(git commit-tree "HEAD^{tree}" -p HEAD -p "$side" -m "Add the feature")"; git reset -q --hard "$c"
EDIT
check "another branch than the run branch" fail "not on the run branch 'fabro/run/01RUN'" <<'EDIT'
mkdir -p .fidfab; printf 'FIDFAB_BRANCH=fabro/run/01RUN\n' > .fidfab/run.env; echo .fidfab > .git/info/exclude
EDIT
check "base from run.env" fail "unusable base branch" <<'EDIT'
mkdir -p .fidfab; printf 'FIDFAB_BRANCH=topic\nFIDFAB_BASE_BRANCH=topic\n' > .fidfab/run.env; echo .fidfab > .git/info/exclude
EDIT
check "no run branch recorded" fail "no run branch recorded" <<<'rm .fidfab/run.env'
# A replacement object shows the checks the pull request's tree while the push would send the
# changed commit; the working tree is checked out from the replaced view, so it looks clean.
check "replacement object hiding changed content" fail "refusing to push" <<'EDIT'
echo extra >> a; git commit -qam "Add the feature with its test"
good="$(git commit-tree "origin/topic^{tree}" -p origin/main~1 -m "Add the feature with its test")"
git replace HEAD "$good"; git reset -q --hard
EDIT
check "workspace fsmonitor not run" pass "pushed 1 rewritten commit(s)" <<'EDIT'
git config core.fsmonitor "touch $ORIGIN/../fsmonitor-ran; false"
EDIT
n_fsmon=$n
check "workspace pre-push hook not run" pass "pushed 1 rewritten commit(s)" <<'EDIT'
printf '#!/bin/sh\nexit 1\n' > .git/hooks/pre-push; chmod +x .git/hooks/pre-push
EDIT
# With a token the pull request must be open with this branch as its head; its base is the base.
GH_TOKEN=fake FAKE_PR=$'OPEN\ttopic\tmain' \
  check "open pull request" pass "pushed 1 rewritten commit(s)" <<<':'
GH_TOKEN=fake FAKE_PR=$'CLOSED\ttopic\tmain' \
  check "closed pull request" fail "is not open" <<<':'
GH_TOKEN=fake FAKE_PR=$'OPEN\tother\tmain' \
  check "pull request of another branch" fail "is not open" <<<':'
GH_TOKEN=fake FAKE_PR='' check "no pull request" fail "no pull request found" <<<':'
if [[ -e "$tmp/r$n_fsmon/fsmonitor-ran" ]]; then
  echo "FAIL workspace fsmonitor not run: the fsmonitor command ran"; fail=1
fi
exit $fail
