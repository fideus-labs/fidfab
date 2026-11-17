# Task plan: switch Codex from the luna model to terra

## Goal

Every Codex stage in fidfab (review, roadmap critique, personal-data decision) runs on the
terra model instead of luna: the `fidfab-codex-acp` alias, its default model ID, the baked
Codex config, the workflows, tests and documentation.

## Phases

### Phase 1: Study
**Status:** complete

Find every luna reference and confirm the terra model ID the installed Codex knows.

### Phase 2: Implement
**Status:** complete

Rename the alias and override variable, change the default model ID, update components and
the `large` workflow, sync component copies, update README and the rendered graph.

### Phase 3: Verify
**Status:** complete

Run the checks AGENTS.md requires and exercise the wrapper.

## Acceptance criteria

- [x] `fidfab-codex-acp --model terra` (and no `--model`) resolves to `gpt-6.1-terra`;
      `FIDFAB_MODEL_TERRA` overrides it.
- [x] `docker/config/codex-config.toml` defaults to `gpt-6.1-terra`.
- [x] No `luna` reference remains in components, workflows, docker, tests, README or graphs.
- [x] `tests/test-codex-model.sh` covers the alias resolution and config default on the host
      (CI `validate` job); `tests/test-codex-acp.sh` runs it against the image.
- [ ] `tests/validate-workflows.sh` passes. NOT RUN: `fabro` is not installed in the sandbox and
      installing it needs the network; run it on the host or in CI.
- [x] `scripts/sync-components.sh --check`, `shellcheck -S warning`
      and `node --check tests/acp-smoke.mjs` pass.

## Next Step

Run `tests/validate-workflows.sh` where `fabro` is available; rebuild the image
(`docker/build.sh && tests/test-image.sh`) so the sandbox carries the new wrapper.
