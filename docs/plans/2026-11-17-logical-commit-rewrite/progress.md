# Progress

- 2026-11-18: Surveyed the steward and ship components, the four workflows, the tests and
  Fabro's run-branch and checkpoint documentation; plan written. Installed Fabro
  0.415.0-nightly.0 into `~/.fabro` of the sandbox for `fabro validate`.
- 2026-11-18: Added `components/rewrite-history.fabro` and `prompts/rewrite-history.md`,
  imported as `history` after `steward` in all four workflows, set
  `[run.run_branch] push = false` in the four `workflow.toml`, widened the workspace rule on
  force-pushes to "where a stage explicitly asks you to", synced the components.
- 2026-11-18: Added `tests/check-history-rewrite.sh` (run by `validate-workflows.sh`) and
  `tests/test-history-rewrite.sh`; README and AGENTS.md updated; graphs re-rendered with
  `scripts/render-graphs.sh` against a Fabro server in the sandbox.
- 2026-11-18: Rehearsed the prompt's git commands in scratch repositories. Two changes came
  out of it: the stage starts from the pull request branch, and the push uses
  `--force-with-lease --force-if-includes`.
- 2026-11-18: Passing: `tests/validate-workflows.sh` (4 workflows), `sync-components.sh --check`,
  `test-history-rewrite.sh`, `test-effort-levels.sh` (32 agent nodes), `test-model-aliases.sh`,
  `test-codex-model.sh`, `test-pr-steward.sh`, `test-bootstrap.sh`, `test-build.sh`,
  `test-setup.sh`, `shellcheck -S warning`, `node --check tests/acp-smoke.mjs`. Not run:
  `docker/build.sh && tests/test-image.sh` (no Docker daemon in the sandbox), and a complete
  workflow run.
