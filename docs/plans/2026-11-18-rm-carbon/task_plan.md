# Task plan: remove the Carbon review nodes

## Goal

Remove the Gemini 4 Carbon code review and security review stages from the verification
pipeline of `small`, `medium` and `verify`, because they take too long and cost too much.

## Current Phase

All phases complete

## Next Step

None; hand over to verification.

## Phases

### Phase 1: Survey
**Status:** complete

Find every node, component, prompt, test and document that exists for, or mentions, the
Carbon reviews.

### Phase 2: Implement
**Status:** complete

Drop the `carbon` and `carbon_security` imports from the three workflow graphs, delete the two
components and their four prompts, fix the prompts and `workflow.toml` comments that refer to
them, sync the vendored copies, re-render the graphs, update README and
`docs/vertex-ai-litellm.md`.

### Phase 3: Verify
**Status:** complete

Run the repository checks listed in AGENTS.md and look for leftovers (orphaned prompts,
dangling references).

## Acceptance criteria

- [x] `small`, `medium` and `verify` run coverage, CodeRabbit, Codex review, Claude review, security review, personal-data audit, commit and PR, steward, with no Carbon stage; `large` is unchanged.
- [x] `components/carbon-review.fabro`, `components/carbon-security-review.fabro` and their four prompts are gone from `components/` and from every vendored copy.
- [x] No remaining prompt tells an agent that a Carbon review ran or points at a Carbon review file.
- [x] Every prompt under `components/prompts/` is still referenced, and every `@prompt` and `import=` path resolves.
- [x] `tests/validate-workflows.sh`, `scripts/sync-components.sh --check`, `tests/test-effort-levels.sh`, `tests/test-model-aliases.sh`, `tests/test-setup.sh` and `shellcheck -S warning` pass.
- [x] README, `docs/vertex-ai-litellm.md` and `docs/graphs/*.svg` describe the pipeline without the Carbon reviews.

## Decisions Made

| Decision | Rationale |
|----------|-----------|
| Keep `gemini-4-carbon` in the LiteLLM proxy model list, the Fabro catalog block and the setup tests | The task names the review nodes. The model registration is host-side setup that costs nothing per run, and removing it rewrites `setup.sh`, `litellm-proxy.sh` and most of the litellm part of `tests/test-setup.sh`. The docs now say that no workflow uses the model. Left as a follow-up decision; see `findings.md`. |
| No new test script | The change only removes stages. The existing checks cover what could break: `fabro validate` (dangling imports, prompt paths, edges), the sync check, and the effort-level scan (31 agent nodes before, 27 after). The Carbon stages were the last shipped nodes with a Gemini effort, so `tests/test-effort-levels.sh` gained a `gemok` fixture, a native node with `reasoning_effort="medium"`, to keep that validation exercised. Orphaned files were checked by hand; see `progress.md`. |
| `.github/workflows/ci.yml` untouched | Nothing in it refers to the Carbon reviews. |

## Errors Encountered

| Error | Attempt | Resolution |
|-------|---------|------------|
| `fabro graph` failed: no `settings.toml`, then `server.auth.methods: field is required` with a hand-written one | 1, 2 | Scripted `fabro install` under a scratch `HOME` with placeholder tokens; see `findings.md` |
| `pgrep -af fabro`, run to confirm the scratch server had stopped, also matched the sandbox driver and printed its whole command line, environment included | 1 | Switched to `pgrep -x fabro`; nothing was written to a file. See `findings.md` |

## Notes on the acceptance criteria

All met. Not verified here: a live run of the shortened pipeline on a Fabro server, and
`docker/build.sh && tests/test-image.sh` (no docker daemon in the sandbox; the image is not
changed).
