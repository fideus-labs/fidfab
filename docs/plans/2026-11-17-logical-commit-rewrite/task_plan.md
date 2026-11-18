# Task plan: rewrite the PR history into logical commits

## Goal

After the PR steward, a Claude opus stage at medium effort rewrites the branch history into
logically related commits with meaningful messages and force-pushes the PR branch. Fabro's
`[run.run_branch] push = false` keeps the checkpoint commits local, so only the stages' own
pushes reach GitHub and the pull request ends with a clean history.

## Current Phase

All phases complete

## Next Step

None; hand over to verification.

## Phases

### Phase 1: Survey
**Status:** complete

How Fabro checkpoints and pushes the run branch, what a run's history looks like, where the
steward sits in each workflow, and which tests and documents describe the stages.

### Phase 2: Implement
**Status:** complete

Add the rewrite stage and its prompt after the steward in every workflow, set
`[run.run_branch] push = false`, sync the vendored components, add tests, update the README
and the graphs.

### Phase 3: Verify
**Status:** complete

Run the repository checks listed in AGENTS.md.

## Acceptance criteria

- [x] Every workflow with a steward runs a Claude opus node at `--effort medium` directly after
      it, on the path that opened a pull request only.
- [x] The prompt has the stage group the branch's commits into logical commits with meaningful
      messages, keep the tree unchanged, and force-push the PR branch.
- [x] Every `workflow.toml` sets `[run.run_branch] push = false`.
- [x] Tests pin the node (agent, model, effort, position) and the setting.
- [x] `tests/validate-workflows.sh`, `scripts/sync-components.sh --check`,
      `tests/test-effort-levels.sh`, `tests/test-model-aliases.sh` and `shellcheck -S warning` pass.
- [x] README, AGENTS.md and the rendered graphs describe the new stage and the setting.

## Errors Encountered

| Error | Attempt | Resolution |
|-------|---------|------------|
| `fabro graph` failed: no server, then no ready LLM provider | 1 | Scripted `fabro install`, placeholder `LITELLM_API_KEY`, `scripts/setup.sh litellm`; see `findings.md` |
| `git push --force-with-lease` after a fetch overwrote an unintegrated commit in the rehearsal | 1 | Prompt and lint require `--force-with-lease --force-if-includes` |
| A process listing (`pgrep -fa fabro`) printed the sandbox driver's command line, which holds the run's credentials, into the stage output | 1 | Nothing reached a file; reported to the operator, who decides on rotation. Use `fabro server status` instead |

## Notes on the acceptance criteria

All met. Not verified here: a complete workflow run (needs Docker and the agent
subscriptions), so the rewrite stage itself has not run; its git commands were rehearsed in
scratch repositories and the `push = false` setting was read back from a server-created run.
`.github/workflows/ci.yml` is unchanged (the push token lacks the `workflow` scope); the lint,
its self-test `tests/test-history-rewrite.sh` and `tests/test-rewrite-push.sh` run in CI
through `tests/validate-workflows.sh`.

Follow-up for a maintainer: `tests/test-model-aliases.sh` and `tests/test-effort-levels.sh`
are not in CI.
