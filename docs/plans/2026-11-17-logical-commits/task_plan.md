# Task plan: logical commits after the steward

## Goal

After the steward node, add a node with Claude opus at medium effort that rewrites the commit
history of the topic branch into logically related commits with meaningful commit messages,
and force-pushes the pull request branch.

## Current Phase

All phases complete

## Next Step

None; hand over to verification.

## Phases

### Phase 1: Survey
**Status:** complete

Read the steward component, the commit and pull request stages, the effort and model alias
tests, and how Fabro checkpoints, pushes and builds a stage's preamble.

### Phase 2: Implement
**Status:** complete

Add `components/logical-commits.fabro` and `components/prompts/logical-commits.md`, import the
component after `steward` in the four workflows, sync the vendored components, cover the new
stage with a test, update the README and re-render the graphs.

### Phase 3: Verify
**Status:** complete

Run the repository checks listed in AGENTS.md.

## Acceptance criteria

- [x] `small`, `medium`, `large` and `verify` run a history rewrite stage directly after
      `steward`; a run without changes (no pull request) does not reach it.
- [x] The stage is Claude Code with `--model opus --effort medium`, and
      `tests/test-effort-levels.sh` accepts it without an override.
- [x] The prompt follows the one in the task: `merge.conflictstyle diff3`, a rebase target
      taken from the base branch, a rewrite into logical commits with new messages, a
      force-push of the pull request branch.
- [x] The rewrite cannot change the code or discard commits it has not seen: the prompt
      requires an identical tree before the push and a push that is leased to the examined
      remote commit.
- [x] The stage does not receive earlier stage output (review comment text) in its preamble.
- [x] A test fails when a workflow that imports the steward lacks the stage or places it
      elsewhere.
- [x] `tests/validate-workflows.sh`, `scripts/sync-components.sh --check`,
      `tests/test-effort-levels.sh`, `tests/test-model-aliases.sh` and `shellcheck -S warning`
      pass.
- [x] README describes the stage and what it leaves behind.

## Errors Encountered

| Error | Attempt | Resolution |
|-------|---------|------------|
| `fabro graph` refused to render: no server settings, then no ready LLM provider | 1 | Scripted `fabro install` and a placeholder LiteLLM provider in the sandbox (see `findings.md`) |

## Notes on the acceptance criteria

All met, with two limits a reader should know:

- The fourth criterion is met by what the prompt instructs and `tests/test-logical-commits.sh`
  pins in its text. The stage was not run in a live Fabro run; its commands were exercised by
  hand in a scratch repository (see `findings.md`).
- The rewritten branch still ends with the empty checkpoint commits of the nodes that run
  after the rewrite. Fabro adds and pushes them; removing them needs a run-wide setting that
  this change leaves alone (see `findings.md`).

Two deviations from the prompt quoted in the task, both explained in `findings.md`: the rebase
target is the merge base with the base branch rather than its tip, and the force-push carries
an explicit lease.
