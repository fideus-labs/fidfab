# Task Plan: Make the CodeRabbit stage detect a missing login and still review

## Goal

When CodeRabbit cannot review (rejected or missing key, signed out, rate limit, outage), the
`coderabbit` stage says why in plain words and reviews the branch with Claude's built-in review
instead of finishing with nothing reviewed.

## Next Step

Human review of this plan at the gate; then start Phase 1 (test first).

## Current Phase

Phase 1 (planning is complete; nothing is implemented yet)

## Context

What happened in the failing run (reproduced in this sandbox, CodeRabbit CLI 0.9.5):

1. `CODERABBIT_API_KEY` is set, but it is a **user** API key. The CLI rejects it:
   `API key authentication failed: User API keys are not supported for the CLI. Please generate
   an agentic API key from your CodeRabbit settings.` `fidfab-bootstrap` sends that message to
   `/dev/null` and logs only "CodeRabbit login failed".
2. `fidfab-coderabbit available` then reports **available** while signed out. It greps
   `coderabbit auth status --agent` for `authenticated`, and the signed-out output is
   `{"type":"status","phase":"auth","status":"not_authenticated","authenticated":false}`,
   which contains that word twice. This is the bug: the fallback to the built-in review that the
   component already has is never taken.
3. The `review` node runs, `coderabbit review --agent` exits 1 with an auth error, and the
   prompt tells the agent to "say so and finish". Result: no review of any kind, as reported.

One part no code change can fix: **the key in the Fabro vault must be replaced by an Agentic API
key** (`app.coderabbit.ai/settings/api-keys`, or `app.eu.coderabbit.ai/...` for EU), then
`fabro secret set CODERABBIT_API_KEY`. Until then, the fixed workflow uses the built-in review
and says so.

Constraints that shape the plan:

- `fabro` and a Docker daemon are not available in the sandbox, so `tests/validate-workflows.sh`
  and `tests/test-image.sh` cannot run here. The plan therefore changes **no `.fabro` graph**;
  only helpers, prompts, tests and docs. The graph already has the right shape.
- Prompts are rendered when the run is created, so anything found out in the sandbox (the
  reason CodeRabbit is unavailable) has to reach the agent through a file or command output.

## Phases

### Phase 1: Host-side test for the wrapper (test first)

- [ ] Add `tests/test-coderabbit-wrapper.sh`, modelled on `tests/test-pr-steward.sh`: a stub
      `coderabbit` on `PATH` driven by environment variables, a scratch git repository, and
      `ok` / `FAIL` lines with a final exit status. Cases:
  1. status `"authenticated":false` (the exact line above) -> `available` exits non-zero.
     This case fails against today's wrapper; confirm that before changing the wrapper.
  2. status `"authenticated":true` -> `available` exits 0.
  3. status output empty, malformed, or the status command failing -> non-zero.
  4. signed out, `CODERABBIT_API_KEY` set, stub login succeeds -> wrapper logs in, exits 0.
  5. signed out, stub login prints the "User API keys are not supported" message containing
     the key -> non-zero; the output names the Agentic API key and the settings URL; the key
     text appears nowhere in stdout, stderr or `.fidfab/reviews/coderabbit-unavailable.md`.
  6. `CODERABBIT_REGION=eu` -> the stub sees `--region eu` on login.
  7. `review`: stub emits findings and a `complete` event, exit 0 -> wrapper exits 0, output
     is on stdout and in `.fidfab/reviews/coderabbit.md`, and `--agent --base <base>` was passed.
  8. `review`: stub emits the `environment_unsupported` auth error and exits 1 -> wrapper
     exits 3 and prints a one-line reason.
  9. `review`: `complete` with `status: review_skipped` and exit 0 -> wrapper exits 3.
  10. `review`: findings followed by an `error` event, exit 1 -> wrapper exits 3 (an
      interrupted review is not a review).
- [ ] Wire it into `.github/workflows/ci.yml` next to the other host-side tests and into the
      Verification list in `AGENTS.md`.
- **Status:** pending

### Phase 2: Fix `fidfab-coderabbit`

File: `docker/rootfs/usr/local/bin/fidfab-coderabbit`.

- [ ] `available`: decide from parsed JSON, not from a word match. Take the output of
      `timeout 60 coderabbit auth status --agent`, and report available only if `jq` finds an
      object with `.authenticated == true`. Non-JSON lines are ignored
      (`jq -R 'fromjson?'`). Anything else is unavailable.
- [ ] `available`, when signed out and `CODERABBIT_API_KEY` is set: run the new `login` once
      and check the status again. This covers a resumed or rewound run and the dev container.
- [ ] New `login` subcommand: `coderabbit auth login [--region $CODERABBIT_REGION] --api-key
      $CODERABBIT_API_KEY`, with the output captured, the key replaced by `<redacted>`, and
      the CLI's own reason printed. For the user-key rejection add one line of advice: create
      an Agentic API key at the settings URL and store it with
      `fabro secret set CODERABBIT_API_KEY`. Exit 0 on success, 1 on failure, 1 with
      "CODERABBIT_API_KEY is not set" when there is no key.
- [ ] Whenever `available` or `login` fails, write the reason (redacted) to
      `.fidfab/reviews/coderabbit-unavailable.md`; remove that file when `available` succeeds.
      The fallback prompt and the PR stage read it.
- [ ] `review`: stop using `exec`. Run `coderabbit review --agent --base "$base" "$@"`, `tee`
      the output to `.fidfab/reviews/coderabbit.md`, then classify: exit 0 only when the CLI
      exited 0, there is no `"type":"error"` event, and `complete` is not `review_skipped`.
      Otherwise print `[fidfab-coderabbit] no review: <phase>/<status>: <message>` on stderr,
      write the same to `coderabbit-unavailable.md`, and exit 3. Exit 2 from `--gate` passes
      through unchanged (nothing uses it today).
- [ ] Update the usage header; keep `set -euo pipefail` and shellcheck clean.
- [ ] `tests/test-coderabbit-wrapper.sh` passes.
- **Status:** pending

### Phase 3: Bootstrap and setup report the real reason

- [ ] `docker/rootfs/usr/local/bin/fidfab-bootstrap`: replace the silenced
      `coderabbit auth login ... >/dev/null 2>&1` with `fidfab-coderabbit login`, and log its
      (redacted) reason in the warning. Bootstrap still never fails because of CodeRabbit.
      Tolerate the helper being absent from `PATH` (host-side `tests/test-bootstrap.sh`).
- [ ] `tests/test-bootstrap.sh`: one case with a stub `fidfab-coderabbit` and
      `CODERABBIT_API_KEY` set, asserting the log carries the stub's reason and bootstrap
      still writes `run.env`. Existing cases must pass unchanged.
- [ ] `scripts/setup.sh` `step_coderabbit`: the note names the **Agentic** API key, says a
      user API key is rejected by the CLI, and gives the US and EU settings URLs. No
      validation call from the host (it would change the host's own CodeRabbit login).
      `tests/test-setup.sh` must still pass.
- **Status:** pending

### Phase 4: Prompts fall back instead of stopping

- [ ] New partial `components/prompts/partials/builtin-review.md` holding the built-in review
      procedure now in `claude-builtin-review.md` (review `fidfab-diff`, save findings to
      `.fidfab/reviews/coderabbit.md` with the first line `CodeRabbit unavailable; review
      produced by Claude Code built-in review`, fix, write `coderabbit-response.md`). Add: the
      response starts with the reason from `.fidfab/reviews/coderabbit-unavailable.md` when
      that file exists.
- [ ] `components/prompts/claude-builtin-review.md`: include the partial; no behaviour change
      beyond stating the reason.
- [ ] `components/prompts/coderabbit-review-fix.md`:
  - step 1 becomes "Run `fidfab-coderabbit review`; it saves the raw output to
    `.fidfab/reviews/coderabbit.md` itself".
  - replace the final "say so and finish" paragraph: if the command exits 3 (no review ran:
    authentication, rate limit, skipped or interrupted review), do not log in, do not look
    for credentials, do not retry more than once for a rate limit; state the reason at the
    top of `coderabbit-response.md` and then do the built-in review from the partial. Never
    report the change as reviewed by CodeRabbit, and never invent CodeRabbit findings.
  - if a later confirmation run (step 4) exits 3, keep the findings already handled and
    note that the confirmation run did not happen.
- [ ] `components/prompts/pull-request.md`: the Verification section says which review ran
      (CodeRabbit or built-in) and, for built-in, the reason from `coderabbit-unavailable.md`.
- [ ] `scripts/sync-components.sh`, then `scripts/sync-components.sh --check`.
- **Status:** pending

### Phase 5: In-image test and documentation

- [ ] `tests/test-coderabbit.sh`: in the unauthenticated branch assert that
      `fidfab-coderabbit available` exits non-zero (this is the check CI runs, and it would
      have caught the bug); in the authenticated branch log in through
      `fidfab-coderabbit login` and assert `fidfab-coderabbit review` exits 0 in the scratch
      repository. `tests/test-tools.sh`: check `jq` is present if it is not already.
- [ ] `README.md`: CodeRabbit section (Agentic key, the user-key error and what the run does
      then), the `coderabbit-review.fabro` row, the test list. `CONTRIBUTING.md` test list.
- [ ] `AGENTS.md`: Verification line for the new test; one line under the learned constraints
      that `coderabbit auth status --agent` prints `not_authenticated` /
      `"authenticated":false` and must be parsed, not matched by word.
- **Status:** pending

### Phase 6: Verification

- [ ] `tests/test-coderabbit-wrapper.sh`, `tests/test-bootstrap.sh`, `tests/test-setup.sh`,
      `tests/test-pr-steward.sh`, `tests/test-build.sh`.
- [ ] `scripts/sync-components.sh --check`.
- [ ] `shellcheck -S warning scripts/*.sh tests/*.sh docker/build.sh
      docker/rootfs/usr/local/bin/fidfab-*`; `node --check tests/acp-smoke.mjs`.
- [ ] Live check in this sandbox with the real CLI and the (rejected) key, using the edited
      helper from the checkout: `available` exits non-zero and prints the Agentic-key advice;
      `review` exits 3; neither prints the key.
- [ ] `tests/validate-workflows.sh` if `fabro` is present; otherwise record in `progress.md`
      that it is left to CI, with the reason (no `.fabro` file changed, prompts only).
- [ ] Update `progress.md` and the phase statuses here.
- **Status:** pending

## Acceptance Criteria

1. With `coderabbit auth status --agent` printing
   `{"type":"status","phase":"auth","status":"not_authenticated","authenticated":false}`,
   `fidfab-coderabbit available` exits non-zero. With `"authenticated":true` it exits 0. With
   empty or malformed output it exits non-zero.
2. With a key the CLI rejects, `fidfab-coderabbit available` and the bootstrap log both show
   the CLI's reason and the advice to create an Agentic API key, and the key's text appears in
   no output and no file under `.fidfab/`.
3. Signed out with a valid key in the environment, `fidfab-coderabbit available` logs in and
   exits 0.
4. `fidfab-coderabbit review` exits 0 only for a completed review; it exits 3 with a one-line
   reason for an auth error, any error event, or `review_skipped`; the raw output is in
   `.fidfab/reviews/coderabbit.md` in every case.
5. `components/prompts/coderabbit-review-fix.md` no longer tells the agent to finish without a
   review; on exit 3 it directs the built-in review, and both prompts take that procedure from
   one partial.
6. In a run with the current (user) key, the stage sequence is `check` failed -> `wait` ->
   `recheck` failed -> `fallback`, and `.fidfab/reviews/coderabbit-response.md` starts with the
   reason CodeRabbit was not used followed by built-in review findings. (Observable on the next
   Fabro run; the wrapper behaviour behind it is covered by criteria 1 and 2.)
7. `tests/test-coderabbit-wrapper.sh` exists, runs in CI, is listed in `AGENTS.md`, and passes.
   Case 1 fails against the wrapper as it is on `main`.
8. All commands in Phase 6 pass, and no file under `.fabro/workflows/*/components/` differs
   from `components/` (`scripts/sync-components.sh --check`).
9. No `.fabro` graph and no `workflow.toml` is changed.

## Risks and Open Questions

1. **The vault key needs replacing (human action).** This change makes the run degrade
   properly; a real CodeRabbit review needs an Agentic API key in `CODERABBIT_API_KEY`.
2. **Three-minute wait on a permanent failure.** With the graph unchanged, a rejected key
   still goes through `wait` before the fallback. Removing that needs routing labels on
   `check` (`available` / `retry` / unlabelled fallback), which is a `.fabro` change that
   cannot be validated in this sandbox. Proposed as a follow-up; say at the gate if you want it
   in this change, validated by CI only.
3. **Undocumented event shapes.** Only `complete` / `review_skipped` and exit code 1 are
   documented for `review --agent`; the rate-limit event shape is not. The wrapper therefore
   treats any non-zero exit or any `error` event as "no review" instead of matching specific
   statuses, and passes the CLI's message through.
4. **The agent can still misreport.** The fallback after a mid-stage failure is a prompt
   instruction, not a graph edge. The pre-check fix makes that path rare (key revoked or rate
   limit between `check` and `review`).
5. **Untracked files.** `coderabbit review --base` leaves untracked files out unless
   `--include-untracked` is passed. `fidfab-diff` marks new files intent-to-add, which
   probably brings them in, but this is not verified. Out of scope here; noted in
   `findings.md`.
6. **Redaction.** The key is removed by literal replacement of `$CODERABBIT_API_KEY` in
   captured output (not with `sed`, so special characters in a key cannot break it).

## Size

One focused session: one helper (about 60 lines), one new test, small edits to bootstrap,
setup, three prompts, one in-image test and the docs. No split needed.

## Decisions Made

| Decision | Rationale |
|----------|-----------|
| Parse `auth status --agent` with `jq`, require `.authenticated == true` | The word match is the bug; the skill's own contract is "proceed only on `authenticated: true`" |
| No `.fabro` graph change | The graph is already right once `available` tells the truth; `fabro validate` cannot run in the sandbox |
| `review` exits 3 for "no review ran" | Gives the prompt one unambiguous signal instead of asking the agent to interpret NDJSON errors |
| Prompt-level fallback after a failed `review` | Covers failures after the pre-check without graph changes |
| Reason recorded in `.fidfab/reviews/coderabbit-unavailable.md` | Prompts are rendered at run creation; a file is how sandbox facts reach later stages |
| `available` retries the login itself | Makes the check self-contained after resume or rewind and in the dev container |
| No host-side key validation in `setup.sh` | It would overwrite the operator's own CodeRabbit CLI login |

## Errors Encountered

| Error | Attempt | Resolution |
|-------|---------|------------|
| `coderabbit auth login --api-key` rejected: user API keys not supported | 1 | Not a code fault; recorded as the human action in Risks 1 |
| `fabro` not installed, no Docker daemon in the sandbox | 1 | Plan avoids `.fabro` changes; validation and image tests left to CI |

## Notes

- Never edit `.fabro/workflows/*/components/`; change `components/` and run
  `scripts/sync-components.sh`.
- Never print or store `CODERABBIT_API_KEY`; test for that explicitly (Phase 1, case 5).
