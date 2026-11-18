#!/usr/bin/env bash
# test-rewrite-push.sh — host-side check of fidfab-rewrite-push against scratch repositories
# with a bare origin: it pushes a rewritten history only when HEAD's tree is the pull
# request's tree and no checkpoint metadata is left, refuses everything else without
# touching origin, and does not overwrite a push made after the rewrite started.
set -euo pipefail
cd "$(dirname "$0")/.."
bin="$PWD/docker/rootfs/usr/local/bin"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.com \
  GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.com \
  GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export PATH="$bin:$PATH"

fail=0; n=0
# setup <dir>: origin (bare) with main and a pull request branch "topic" of a feature commit
# and two checkpoint commits; <dir>/work tracks origin/topic and has the same three commits
# squashed into one, the tree unchanged.
setup() {
  local d="$1"
  git init -q --bare -b main "$d/origin.git"
  git init -q -b main "$d/seed"
  (
    cd "$d/seed"
    echo base > a; git add a; git commit -qm base
    git remote add origin "$d/origin.git"; git push -q origin main
    git checkout -q -b topic
    echo feature >> a; git commit -qam "Add the feature"
    echo test > t; git add t; git commit -qm "fabro(01RUN): implement (success)"
    git commit -q --allow-empty -m "fabro(01RUN): verify (success)"
    git push -q origin topic
  )
  git clone -q -b topic "$d/origin.git" "$d/work"
  (
    cd "$d/work"
    git reset -q --soft origin/main
    git commit -qm "Add the feature with its test" -m "Why it is needed."
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
  ( cd "$d/work" && fidfab-rewrite-push ) >"$tmp/log" 2>&1 || rc=$?
  after="$(git -C "$d/origin.git" rev-parse topic)"
  head="$(git -C "$d/work" rev-parse HEAD 2>/dev/null || true)"
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
git reset -q --soft origin/main
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
check "detached HEAD" fail "HEAD is detached" <<<'git checkout -q --detach'
check "rebase in progress" fail "rebase, merge or cherry-pick is in progress" <<<'mkdir .git/rebase-merge'
check "no upstream" fail "has no upstream" <<<'git branch -q --unset-upstream'
check "upstream on another remote" fail "expected 'origin/topic'" <<'EDIT'
git remote add fork "$ORIGIN"; git fetch -q fork; git branch -q -u fork/topic
EDIT
check "upstream is another branch" fail "expected 'origin/topic'" <<'EDIT'
git fetch -q origin main; git branch -q -u origin/main
EDIT
exit $fail
