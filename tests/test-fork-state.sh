#!/usr/bin/env bash
# test-fork-state.sh — host-side check of fidfab-state: after a stage, .fidfab/ is noted with
# the checkpoint and pushed; a fork, a fresh clone of the checkpoint on fabro/run/<its id>, gets
# it back through the first wrapper that finds .fidfab/run.env missing, past the fork's own
# checkpoints, which have no note. A local bare repository stands in for origin.
set -euo pipefail
cd "$(dirname "$0")/.."
export PATH="$PWD/docker/rootfs/usr/local/bin:$PATH" GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }
checkpoint() { git commit -q --allow-empty -m "fabro($1): $2 (success)" -m "Fabro-Run: $1"; }
fresh() { rm -rf .fidfab; : > .git/info/exclude; git checkout -q -B "fabro/run/$1" "$2"; }   # a fork's workspace

git init -q --bare "$tmp/origin.git"
git clone -q "$tmp/origin.git" "$tmp/run" 2>/dev/null; cd "$tmp/run"
git commit -q --allow-empty -m "start"
git push -q origin HEAD:main
# A commit that is not a checkpoint, or a checkpoint before run.env exists, is not noted.
mkdir -p .fidfab/reviews
fidfab-state save || fail "save fails outside a checkpoint"
checkpoint 01RUN start
echo 'partial' > .fidfab/reviews/x.md
fidfab-state save
[[ -z "$(git ls-remote origin 'refs/notes/*')" ]] || fail "a note pushed outside a checkpoint or without run.env"
out="$(fidfab-state restore 2>&1)" && fail "restore succeeds outside fabro/run/<id>"
[[ -z "$out" ]] || fail "restore said something outside a run's sandbox: $out"

checkpoint 01RUN review
noted="$(git rev-parse HEAD)"
echo 'FIDFAB_BASE_BRANCH=main' > .fidfab/run.env && echo 'skipped' > .fidfab/reviews/codex-review.md
fidfab-state save
git push -q origin HEAD:fabro/run/01RUN

# The fork: a fresh workspace at the checkpoint. fidfab-diff, like every wrapper that reads
# run.env, restores .fidfab/ first.
git clone -q "$tmp/origin.git" "$tmp/fork" 2>/dev/null; cd "$tmp/fork"
fresh 01FORK "$noted"
fidfab-diff --stat >/dev/null 2>&1 || true
[[ "$(cat .fidfab/reviews/codex-review.md 2>/dev/null)" == skipped ]] || fail "the reviews were not restored"
grep -qx 'FIDFAB_BASE_BRANCH=main' .fidfab/run.env || fail "run.env was not restored"
grep -qxF '.fidfab/' .git/info/exclude || fail ".fidfab/ is not excluded in the fork"
[[ -z "$(git status --porcelain)" ]] || fail "the restore left changes for git: $(git status --porcelain)"

# The fork's stages run no hook: their checkpoints (a gate's, a script's) have no note, and an agent
# may have committed and written to .fidfab/ meanwhile. The next helper restores the note before
# them, and keeps what the stages wrote.
fresh 01FORK "$noted"
git commit -q --allow-empty -m "an agent's commit"
checkpoint 01FORK gate
checkpoint 01FORK pass
mkdir -p .fidfab/reviews && echo 'rerun' > .fidfab/reviews/codex-review.md
fidfab-state restore 2>/dev/null || fail "the note before the fork's checkpoints was not restored"
[[ -f .fidfab/run.env && "$(cat .fidfab/reviews/codex-review.md)" == rerun ]] || fail "the restore lost or overwrote state"

# A checkpoint of the run forked from without a note is a failed save: the older note is stale.
git checkout -q "$noted" && checkpoint 01RUN base
fresh 01FORK HEAD
fidfab-state restore 2>/dev/null && fail "restore took a note older than a failed save"
[[ ! -e .fidfab ]] || fail "a failed save let an older note through"
mkdir .fidfab && echo x > .fidfab/y
[[ -z "$(git status --porcelain)" ]] || fail ".fidfab/ is not out of git when nothing was restored"

# A new run from the branch of a run that left notes takes nothing from it.
fresh 01NEW "$noted"
checkpoint 01NEW start
fidfab-state restore 2>/dev/null && fail "a new run restored the .fidfab/ of the run it started from"
[[ ! -e .fidfab ]] || fail "a new run restored something"

# A note only extracts .fidfab/: whoever pushes one cannot write elsewhere in the workspace.
mkdir -p "$tmp/evil/.fidfab" && echo x > "$tmp/evil/.fidfab/run.env" && echo x > "$tmp/evil/planted"
blob="$(tar czf - -C "$tmp/evil" .fidfab planted | git hash-object -w --stdin)"
git notes --ref=refs/notes/fidfab/01RUN add -f -C "$blob" "$noted" 2>/dev/null && git push -q -f origin refs/notes/fidfab/01RUN
git update-ref -d refs/notes/fidfab/01RUN
fresh 01FORK "$noted"
fidfab-state restore 2>/dev/null || fail "restore of the second note failed"
[[ ! -e planted ]] || fail "a note wrote outside .fidfab/"
echo "test-fork-state: ok"
