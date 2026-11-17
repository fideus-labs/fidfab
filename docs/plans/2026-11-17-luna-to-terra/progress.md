# Progress

## 2026-11-17

- Located all luna references (wrapper, Codex config, two components, `large` workflow,
  README, graph, tests).
- Renamed alias `luna` -> `terra`, `FIDFAB_MODEL_LUNA` -> `FIDFAB_MODEL_TERRA`, default
  `gpt-5.6-luna` -> `gpt-6.1-terra`; applied the same edit to the generated component copies
  (identical to what `scripts/sync-components.sh` produces; `--check` passes).
- Added offline alias-resolution checks (stub `codex-acp`).
- Carbon review: moved those checks to the host-runnable `tests/test-codex-model.sh` (repository
  wrapper and config by default, installed ones from `tests/test-codex-acp.sh`) and replaced the
  grep-based alias lint in `tests/validate-workflows.sh` with `tests/check-model-aliases.sh`
  (parses `--model` in any position, reads only the `case "$model"` block, compares literally),
  covered by `tests/test-model-aliases.sh`. Both new tests run in CI's `validate` job.

## Verification

| Check | Result |
|-------|--------|
| `tests/test-codex-acp.sh` (worktree wrapper first on PATH, real credentials) | pass; live prompt answered by `gpt-6.1-terra` |
| `tests/test-codex-model.sh` (repository files) | pass; against the stale baked wrapper it fails as expected |
| `tests/test-model-aliases.sh` | pass (13 fixture cases plus the repository) |
| `tests/test-bootstrap.sh`, `tests/test-pr-steward.sh` | pass |
| `scripts/sync-components.sh --check` | pass |
| `shellcheck -S warning` on all shell scripts | pass |
| `node --check tests/acp-smoke.mjs` | pass |
| `tests/validate-workflows.sh` | alias check passes; `fabro validate` not run: `fabro` not installed |
| `docker/build.sh && tests/test-image.sh` | not run: docker CLI present but no daemon in the sandbox |

## Claude review follow-up

- `fidfab-codex-acp --model luna` now exits 64 with a message pointing to `terra`. A set
  `FIDFAB_MODEL_LUNA` is ignored with a warning on stderr. The README documents
  `FIDFAB_MODEL_TERRA`.
- Using only aliases in workflows (no literal model IDs) is now documented as intended, in
  `check-model-aliases.sh`, the wrapper usage text, AGENTS.md and the README.
- The config-default check in `tests/test-codex-model.sh` now tolerates whitespace around `=`.
- Re-ran `test-codex-model.sh` (12 checks), `test-model-aliases.sh` (14), `test-bootstrap.sh`,
  `test-pr-steward.sh`, `sync-components.sh --check` and shellcheck: all pass.
