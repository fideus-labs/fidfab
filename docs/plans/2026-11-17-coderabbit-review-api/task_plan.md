# Task Plan: Make the CodeRabbit stage detect a failed login and fall back to a real review

## Goal

When CodeRabbit cannot review (login rejected, not authenticated, rate limit, service
error), the `coderabbit` stage must still review the branch with Claude's built-in review
and say why CodeRabbit did not run. It must never end with "nothing was reviewed".

## Current Phase

Phase 1 (planning complete; implementation not started)

## Next Step

Phase 1, step 1: add the `login` subcommand and the JSON-based `available` check to
`docker/rootfs/usr/local/bin/fidfab-coderabbit`.

## Context

The run that prompted this task ended the `coderabbit.review` node with no review at all.
Reproduced in this sandbox (details and command output in `findings.md`):

1. **The vault key is the wrong kind.** `CODERABBIT_API_KEY` is set, but
   `coderabbit auth login --api-key` answers `User API keys are not supported for the CLI.
   Please generate an agentic API key`. This needs an operator action (see Risks); code
   cannot fix it, but code hid it: `fidfab-bootstrap` sends the CLI's output to
   `/dev/null` and logs only "CodeRabbit login failed".
2. **The availability check is a false positive.** `fidfab-coderabbit available` greps
   `coderabbit auth status --agent` for `authenticated`. The signed-out answer is
   `{"type":"status","phase":"auth","status":"not_authenticated","authenticated":false}`,
   which contains that word twice, so the check exits 0. The graph therefore went to
   `review`, never to `wait` or `fallback`. Bootstrap's promise ("the workflow will fall
   back to Claude's built-in review") was not kept.
3. **The review prompt tells the agent to stop.** `coderabbit-review-fix.md` ends with
   "If the CodeRabbit CLI reports a rate limit or authentication failure, say so ... and
   finish". So any failure after the pre-check (rate limit, expired key, outage) also
   produces no review.
4. **No test covers the helper.** `tests/test-coderabbit.sh` only runs the authenticated
   path when a key is present; CI runs it without one.

### Design decisions

| Decision | Rationale |
|----------|-----------|
| Parse `auth status --agent` as JSON and require `.authenticated == true` | The only reliable signal; any other or malformed output counts as unavailable |
| `available` retries the login itself when signed out and a key is set | Makes the existing 3-minute wait useful: a login that failed at bootstrap for a transient reason heals on `recheck` |
| One login implementation, `fidfab-coderabbit login`, used by bootstrap and `available` | Removes the duplicate in bootstrap; one place redacts the key and reports the CLI's reason |
| The review prompt performs the built-in review in the same session when the CLI fails | No graph change is needed, so there is no routing on agent output and nothing new for `fabro validate` to reject (`fabro` is not installed in the sandbox) |
| Built-in review steps move to a shared partial | `claude-builtin-review.md` and the new failure branch of `coderabbit-review-fix.md` must not drift apart |
| Graph topology stays as it is | A rejected key still costs the 3-minute wait before `fallback`. Skipping it needs label routing from a script node; left as a follow-up (see Open questions) |

## Phases

### Phase 1: Fix the helper (`fidfab-coderabbit`)
**Status:** pending

1. Add `fidfab-coderabbit login`: when `CODERABBIT_API_KEY` is empty, print
   `coderabbit: CODERABBIT_API_KEY is not set` to stderr and exit 1. Otherwise run
   `timeout 60 coderabbit auth login ${CODERABBIT_REGION:+--region ...} --api-key ...`,
   capture stdout+stderr, and on failure print `coderabbit: login failed: <CLI message>`
   to stderr with every occurrence of the key replaced by `<redacted>`, exit 1. On success
   print `coderabbit: authenticated`.
2. Rewrite `available`:
   - missing CLI: exit 1 (unchanged).
   - `authenticated()` helper: `timeout 60 coderabbit auth status --agent`, then
     `jq -R 'fromjson? | select(.authenticated == true)'` must produce output. Non-JSON
     lines are ignored; no matching line means not authenticated.
   - if not authenticated and `CODERABBIT_API_KEY` is set, call the login function once
     and check again.
   - exit 0 with `coderabbit: available`, or exit 1 with
     `coderabbit: unavailable: <reason>` on stderr (reason = login error, or the status
     line, key redacted).
3. `review`: keep `coderabbit review --agent --base "$base" "$@"` and its stdout unchanged,
   but stop using `exec`; propagate the exit code, and when it is non-zero print
   `fidfab-coderabbit: review did not complete (exit N); CodeRabbit did not review this
   branch` to stderr.
4. Update the header comment and usage text (the `sed -n` range must still cover it).
5. `shellcheck -S warning docker/rootfs/usr/local/bin/fidfab-coderabbit`.

### Phase 2: Bootstrap reports the reason
**Status:** pending

1. In `fidfab-bootstrap` replace the inline `coderabbit auth login ... >/dev/null 2>&1`
   with a call to `fidfab-coderabbit login`, capturing its stderr.
2. Log `CodeRabbit: authenticated` on success; on failure log
   `warning: <helper message>; the workflow will fall back to Claude's built-in review`.
   Keep the "not set" warning. Bootstrap must still succeed either way.
3. Resolve the helper next to the bootstrap script when it is not on `PATH`
   (`"$(dirname "$0")/fidfab-coderabbit"`), so `tests/test-bootstrap.sh` works on the host.

### Phase 3: Prompts fall back instead of stopping
**Status:** pending

1. Create `components/prompts/partials/builtin-review.md` with the review steps now in
   `claude-builtin-review.md` (review `fidfab-diff`, save findings to
   `.fidfab/reviews/coderabbit.md` with the first line `CodeRabbit unavailable; review
   produced by Claude Code built-in review`, fix, write `coderabbit-response.md`).
2. `claude-builtin-review.md`: keep the heading and intro, include the partial, keep the
   `partials/workspace.md` include.
3. `coderabbit-review-fix.md`: replace the last paragraph. New rule: if
   `fidfab-coderabbit review` exits non-zero or its output has an `error` event and no
   `complete` event (authentication, rate limit, service error), CodeRabbit did not
   review. Keep the raw output in `.fidfab/reviews/coderabbit-error.md`, do not retry in
   a loop, do not try to log in or handle the key, do not invent CodeRabbit findings, and
   then perform the built-in review via `{% include "partials/builtin-review.md" %}`.
   State the reason CodeRabbit did not run at the top of `coderabbit-response.md`. If a
   later re-run (step 4) fails after a first successful review, keep the first review's
   findings and note that the confirmation run failed.
4. Update the header comment of `components/coderabbit-review.fabro` to describe the
   behaviour (no node or edge changes).
5. `scripts/sync-components.sh`, then `scripts/sync-components.sh --check`.

### Phase 4: Tests
**Status:** pending

1. New host test `tests/test-coderabbit-helper.sh` (stub `coderabbit` on `PATH`, as
   `tests/test-pr-steward.sh` stubs `gh`; the stub answers from files in a temp dir and
   logs its arguments). Cases:
   - signed-out JSON, no key: `available` exits 1 (regression for the false positive).
   - `"authenticated":true`: exits 0, no login attempted.
   - signed out, key set, login succeeds: exits 0, login called once with `--api-key`.
   - signed out, key set, login rejected: exits 1, stderr has the CLI's reason and does
     not contain the key.
   - `CODERABBIT_REGION=eu` is passed as `--region eu`.
   - malformed or empty status output: exits 1.
   - no `coderabbit` on `PATH`: exits 1.
   - `review` passes `--agent --base <FIDFAB_BASE_BRANCH from .fidfab/run.env>`, forwards
     extra arguments, and returns the CLI's exit code with the stderr note on failure.
2. `tests/test-bootstrap.sh`: add cases outside the slug table: with a stub `coderabbit`
   whose login fails and `CODERABBIT_API_KEY=cr-secret`, bootstrap still exits 0 and
   records `run.env`, the log has the CLI's reason and not `cr-secret`; with a succeeding
   stub the log has `CodeRabbit: authenticated`.
3. `tests/test-coderabbit.sh` (image): without a key assert `! fidfab-coderabbit available`.
4. Prompt check in the new host test: `coderabbit-review-fix.md` and
   `claude-builtin-review.md` both include `partials/builtin-review.md`, and the review
   prompt no longer contains "and finish".
5. Add the new test to `.github/workflows/ci.yml` (validate job).

### Phase 5: Docs and verification
**Status:** pending

1. `README.md`: CodeRabbit setup section (Agentic API key, not a user API key; the CLI
   rejects user keys; link to the API keys page; what the run does when login fails),
   pipeline step 3 and the `coderabbit-review.fabro` row, the tests table.
2. `scripts/setup.sh` `step_coderabbit`: note that a user API key is rejected.
3. `AGENTS.md` Verification: `tests/test-coderabbit-helper.sh` must pass after any change
   to `fidfab-coderabbit`.
4. Run: `tests/test-coderabbit-helper.sh`, `tests/test-bootstrap.sh`,
   `tests/test-pr-steward.sh`, `tests/test-build.sh`, `scripts/sync-components.sh --check`,
   `shellcheck -S warning scripts/*.sh tests/*.sh docker/build.sh
   docker/rootfs/usr/local/bin/fidfab-*`, `node --check tests/acp-smoke.mjs`,
   `tests/validate-workflows.sh` if `fabro` is available.
5. Manual check in this sandbox against the real CLI (the vault key is a user key):
   `fidfab-coderabbit available` exits 1 and prints the "User API keys are not supported"
   reason. Use the working-tree copy of the helper, not the one baked into the image.
6. Update `progress.md`.

## Acceptance criteria

1. With `coderabbit auth status --agent` returning
   `{"type":"status","phase":"auth","status":"not_authenticated","authenticated":false}`
   and no usable key, `fidfab-coderabbit available` exits 1.
2. With `"authenticated":true` it exits 0 and prints `coderabbit: available`.
3. Signed out with `CODERABBIT_API_KEY` set, `available` attempts exactly one login and
   exits 0 if the status is then authenticated, 1 otherwise.
4. When login is rejected, the CLI's own message appears in the `available` stderr and in
   the bootstrap log; the key value appears in neither.
5. `fidfab-bootstrap` exits 0 whether CodeRabbit login succeeds, fails or has no key.
6. `fidfab-coderabbit review` returns the CLI's exit code and leaves its stdout unchanged.
7. `coderabbit-review-fix.md` instructs the agent to run the built-in review when the CLI
   fails; no prompt tells it to finish without reviewing. Both review prompts take the
   built-in steps from `partials/builtin-review.md`.
8. `scripts/sync-components.sh --check` passes; no node or edge of
   `coderabbit-review.fabro` changed.
9. `tests/test-coderabbit-helper.sh`, `tests/test-bootstrap.sh` and shellcheck pass, and
   the new test runs in CI.
10. In this sandbox, with the current (user) key, `fidfab-coderabbit available` from the
    working tree exits 1 with the "User API keys are not supported" reason.

## Risks and open questions

- **Operator action required, outside this change:** replace the vault secret with an
  Agentic API key (`fabro secret set CODERABBIT_API_KEY`, key from
  https://app.coderabbit.ai/settings/api-keys). Until then every run uses the built-in
  review. After this change that is a working, clearly reported state.
- **`fabro` is not installed in the sandbox**, so `tests/validate-workflows.sh` cannot run
  here. The plan changes no graph structure (comments and prompts only), and CI runs the
  validation. If the implementer changes a node or edge after all, validation in CI is
  the only check.
- **Shape of the authenticated status JSON is not verified.** Only the signed-out answer
  was observed; the code-review skill says to proceed only on `authenticated: true`, and
  the docs show no example. If the real field differs, `available` reports unavailable
  and the run uses the built-in review (safe direction). The image test with a valid key
  (`tests/test-coderabbit.sh`) catches it.
- **`auth status` may not contact the service**, so a rate limit or outage can still
  surface only in `review`. Phase 3 covers that case in the prompt.
- **Running image is older than the workflow.** Prompts are rendered from the workflow,
  helpers come from the image. The new prompt only relies on the exit code and the
  `error` event of `fidfab-coderabbit review`, which the old helper also passes through,
  so it works with an image that has not been rebuilt. The `available` fix needs a
  rebuilt image (`docker/build.sh`).
- **Open question: skip the 3-minute wait for a permanent failure?** A rejected key type
  will not heal in three minutes. Skipping needs `output_schema="routing"` on `check`
  with labelled edges, which cannot be validated here. Proposed as a follow-up; say so
  at the plan gate if it should be part of this change.
- **Open question: validate the key in `scripts/setup.sh`?** Possible only when the host
  has the `coderabbit` CLI or the image. Not planned; the README and the bootstrap log
  now state the requirement.

## Size

One focused session: one helper, a small bootstrap edit, two prompts and a partial, one
new test file and two extended ones, docs. No split needed.

## Errors Encountered

| Error | Attempt | Resolution |
|-------|---------|------------|
| `fabro: command not found` in the sandbox | 1 | Recorded as a risk; plan avoids graph changes |
