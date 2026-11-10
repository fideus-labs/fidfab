#!/usr/bin/env bash
# test-bootstrap.sh — host-side check of the plan slug fidfab-bootstrap records in
# .fidfab/run.env: the plan_slug input, or <date>-<topic branch the run started from> when
# the input is still the default "task". Each case replays a checkout sequence like Fabro's
# in the sandbox (start branch, then fabro/run/<id>) in a scratch repository whose first
# reflog entry, standing in for the clone, is dated 2026-01-02.
set -euo pipefail
cd "$(dirname "$0")/.."
bootstrap="$PWD/docker/rootfs/usr/local/bin/fidfab-bootstrap"

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/home"
export HOME="$tmp/home" GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.com \
  GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.com

fail=0; n=0
check() { # name, expected slug, checkouts after main (created when missing), plan_slug input
  local repo="$tmp/repo$((n += 1))" b got
  git init -q -b main "$repo"
  GIT_COMMITTER_DATE=2026-01-02T12:00:00Z git -C "$repo" commit -q --allow-empty -m init
  for b in $3; do git -C "$repo" checkout -q "$b" 2>/dev/null || git -C "$repo" checkout -q -b "$b"; done
  # A clean environment keeps host credentials away from the credential step.
  ( cd "$repo" && env -i PATH="$PATH" HOME="$HOME" FIDFAB_CACHE="$tmp/cache" FIDFAB_PLAN_SLUG="$4" "$bootstrap" ) >"$tmp/log" 2>&1 || true
  got="$(cd "$repo" && . .fidfab/run.env 2>/dev/null && printf '%s' "$FIDFAB_PLAN_SLUG")" || got="<no run.env>"
  if [[ "$got" == "$2" && ! -e "$repo/pwned" ]]; then echo "ok   $1"; else echo "FAIL $1: got '$got', want '$2'"; cat "$tmp/log"; fail=1; fi
}

run=fabro/run/01TEST
check "dated topic branch replaces the default"  2026-01-02-chunk-cache         "chunk-cache $run"                task
check "slashes become dashes"                    2026-01-02-feature-chunk-cache "feature/chunk-cache $run"        task
check "a dated branch is not dated twice"        2026-10-24-threads             "2026-10-24-threads $run"         task
check "main keeps the default"                   task                           "$run"                            task
check "release branches keep the default"        task                           "release/1.2 $run"                task
check "a detached start keeps the default"       task                           "chunk-cache --detach $run"       task
check "later checkouts do not change the slug"   2026-01-02-chunk-cache         "chunk-cache $run scratch $run"   task
check "no run branch: the current branch counts" 2026-01-02-chunk-cache         "chunk-cache"                     task
# A branch name is repository data: this one would run `touch pwned` if it reached the sed
# script, or run.env unquoted.
# shellcheck disable=SC2016
check "a hostile run branch name is not executed" task 'chunk-cache fabro/run/x|touch${IFS}pwned|e;#' task
check "an explicit slug wins"                    threads                        "chunk-cache $run"                threads
check "an explicit slug is recorded verbatim"    "my plan"                      "chunk-cache $run"                "my plan"

exit "$fail"
