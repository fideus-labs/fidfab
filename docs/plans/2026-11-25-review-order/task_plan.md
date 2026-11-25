# Task plan: run the CodeRabbit review after the Codex and Claude reviews

## Goal

Change the review order of the verification pipeline in `small`, `medium` and `verify` from
CodeRabbit, Codex, Claude to Codex, Claude, CodeRabbit.

## Current Phase

All phases complete

## Next Step

None; hand over to verification.

## Phases

### Phase 1: Survey
**Status:** complete

Find every graph, prompt, test and document that states or depends on the review order.

### Phase 2: Implement
**Status:** complete

Reorder the edge chain (and the import lines, which read in pipeline order) in the three
workflow graphs. Tell the two CodeRabbit-stage prompts that the Codex and Claude reviews were
addressed before them, and list the stages in the new order in `pull-request.md`. Sync the
vendored copies.

### Phase 3: Test
**Status:** complete

Add `tests/test-pipeline-order.sh`, an offline check of the stage order that fails on the old
order, and run it from `tests/validate-workflows.sh`.

### Phase 4: Document
**Status:** complete

README, `docs/workflows.md`, `docs/testing.md`, AGENTS.md; re-render `docs/graphs/*.svg`.

### Phase 5: Verify
**Status:** complete

Run the repository checks listed in AGENTS.md.

## Acceptance criteria

- [x] `small`, `medium` and `verify` run coverage, Codex review, Claude review, CodeRabbit review, security review, personal-data audit, commit and PR, steward, history rewrite, in that order; `large` is unchanged.
- [x] A test fails on the old order (and on any other) and passes on the new one, and `tests/validate-workflows.sh` runs it.
- [x] No prompt states an order that is no longer true; the CodeRabbit fix and the built-in review that stands in for it know the Codex and Claude reviews were addressed first.
- [x] The vendored component copies are in sync (`scripts/sync-components.sh --check`).
- [x] README, `docs/workflows.md` and `docs/graphs/{small,medium,verify}.svg` show the new order; `docs/testing.md` and AGENTS.md name the new test.
- [x] `tests/validate-workflows.sh`, `tests/test-effort-levels.sh`, `tests/test-logical-commits.sh`, `tests/test-model-aliases.sh` and `shellcheck -S warning` pass.

## Decisions Made

| Decision | Rationale |
|----------|-----------|
| The import lines move with the edge chain | The graphs list one import per stage in pipeline order so that the file reads as the process. Fabro does not care about the order of the node statements. |
| `coderabbit-review-fix.md` and `claude-builtin-review.md` name the Codex and Claude response records | The stage that fixes the last review otherwise decides again, without the evidence, on findings an earlier stage already fixed or judged not an issue. `address-claude.md` does the same for the Codex review. The built-in review reads the records only after saving its own findings, as `review-claude.md` keeps the Claude review independent. |
| A new test, `tests/test-pipeline-order.sh`, pins the whole pipeline from the coverage check on, not only the three reviews | Nothing checked the order before; `fabro validate` accepts any. The walk follows the graph from the coverage check anyway, and the full list is what README and `docs/workflows.md` describe. The steward -> history tail repeats what `tests/test-logical-commits.sh` checks. |
| The test also ties the prompts to the order | A prompt that says which reviews were addressed before it is wrong after the next reorder, and no other check would notice. |
| A separate script rather than a case in `tests/test-logical-commits.sh` | That test is about the history rewrite. `validate-workflows.sh` runs both, so CI needs no new step. |
| No reason for the new order in the docs | The task gives none; the docs state the order. |
| Lists that are not the pipeline order stay as they are | The sandbox diagram in README, the prerequisites, `tests/test-image.sh` and its mentions, `scripts/setup.sh` steps and "A usage limit (Claude, Codex, CodeRabbit)" in AGENTS.md list tools and credentials. |

## Errors Encountered

| Error | Attempt | Resolution |
|-------|---------|------------|
| `tests/validate-workflows.sh`: vendored copies out of date | 1 | I had moved the note in `coderabbit-review-fix.md` after the first sync; ran `scripts/sync-components.sh` again |

## Notes on the acceptance criteria

All met. Not verified here: a live run of the reordered pipeline on a Fabro server, and
`docker/build.sh && tests/test-image.sh` (no docker daemon in the sandbox; the image is not
changed).
