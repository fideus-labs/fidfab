# Progress

## 2026-11-17

- Located all luna references (wrapper, Codex config, two components, `large` workflow,
  README, graph, tests).
- Renamed alias `luna` -> `terra`, `FIDFAB_MODEL_LUNA` -> `FIDFAB_MODEL_TERRA`, default
  `gpt-5.6-luna` -> `gpt-5.6-terra`; applied the same edit to the generated component copies
  (identical to what `scripts/sync-components.sh` produces; `--check` passes).
- Added offline alias-resolution checks to `tests/test-codex-acp.sh` (stub `codex-acp`).

## Verification

| Check | Result |
|-------|--------|
| `tests/test-codex-acp.sh` (worktree wrapper first on PATH, real credentials) | pass; live prompt answered by `gpt-5.6-terra` |
| `scripts/sync-components.sh --check` | pass |
| `shellcheck -S warning` on all shell scripts | pass |
| `node --check tests/acp-smoke.mjs` | pass |
| `tests/validate-workflows.sh` | not run: `fabro` not installed |
| `docker/build.sh && tests/test-image.sh` | not run: docker CLI present but no daemon in the sandbox |
