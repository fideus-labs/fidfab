# Progress

- 2026-11-25: Surveyed the graphs, components, prompts, tests and docs for the review order;
  plan written.
- 2026-11-25: Reordered the edge chain and the import lines in `small`, `medium` and `verify`;
  told `coderabbit-review-fix.md` and `claude-builtin-review.md` that the Codex and Claude
  reviews were addressed first; listed the stages in the new order in `pull-request.md`; synced
  the vendored copies.
- 2026-11-25: Added `tests/test-pipeline-order.sh` and called it from
  `tests/validate-workflows.sh`. Mutation checks, each restored afterwards: the old chain in one
  workflow, the three graphs as on `main`, `coderabbit-review-fix.md` as on `main`, a later
  record named in `address-codex.md`, and `verify` without its coverage import all fail.
- 2026-11-25: README, `docs/workflows.md`, `docs/testing.md` and AGENTS.md updated.
- 2026-11-25: `docs/graphs/{small,medium,verify}.svg` re-rendered with `scripts/render-graphs.sh`
  (`large.svg` came out byte-identical); the rendered edges read coverage -> codex -> claude ->
  coderabbit -> security in all three.
- 2026-11-25: Passing with Fabro 0.423.0-nightly.0: `tests/validate-workflows.sh` (4 workflows),
  `sync-components.sh --check`, `test-pipeline-order.sh` (3 workflows), `test-logical-commits.sh`
  (4 workflows), `test-effort-levels.sh` (28 agent nodes), `test-model-aliases.sh`,
  `test-setup.sh`, `test-bootstrap.sh`, `test-build.sh`, `test-codex-model.sh`,
  `test-pr-steward.sh`, `test-review-wrappers.sh`, `shellcheck -S warning`,
  `node --check tests/acp-smoke.mjs`, `git diff --check`.
  Not run: `docker/build.sh && tests/test-image.sh` (no docker daemon in the sandbox).
- 2026-11-25: Claude review round: `tests/test-pipeline-order.sh` now also fails a stage imported
  a second time (a CodeRabbit import ahead of `coverage` in `verify` passed `fabro validate` and
  the test before; it now fails, and so does the new `again` fixture with the check removed).
  `coderabbit-review-fix.md`, `claude-builtin-review.md` and `address-claude.md` say the earlier
  reviews were addressed "in a workflow that runs them", for imports into other workflows.
  `validate-workflows.sh`, `sync-components.sh --check`, `test-pipeline-order.sh`,
  `test-logical-commits.sh`, `test-effort-levels.sh`, `test-model-aliases.sh`,
  `shellcheck -S warning`, `node --check` and `git diff --check` pass.
