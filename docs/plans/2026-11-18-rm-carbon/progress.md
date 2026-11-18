# Progress

- 2026-11-18: Surveyed the Carbon review nodes, components, prompts, tests and docs; plan written.
- 2026-11-18: Removed the `carbon` and `carbon_security` imports and edges from `small`, `medium`
  and `verify`; deleted the two components and four prompts; dropped the Carbon mentions from
  `address-claude.md`, `pull-request.md` and the four `workflow.toml`; synced the vendored copies.
- 2026-11-18: README, `docs/vertex-ai-litellm.md` and the comment `setup.sh litellm` writes into
  `settings.toml` updated; `docs/graphs/{small,medium,verify}.svg` re-rendered with
  `scripts/render-graphs.sh` (`large.svg` came out byte-identical).
- 2026-11-18: Passing with Fabro 0.415.0-nightly.0: `tests/validate-workflows.sh` (4 workflows),
  `sync-components.sh --check`, `test-effort-levels.sh` (27 agent nodes), `test-model-aliases.sh`,
  `test-setup.sh`, `test-bootstrap.sh`, `test-build.sh`, `test-codex-model.sh`,
  `test-pr-steward.sh`, `shellcheck -S warning`, `node --check tests/acp-smoke.mjs`.
  A one-off script found no dangling `import=`, `@prompt` or `include`, and no component, prompt
  or partial left unreferenced (10 components, 26 prompts, 4 partials).
  Not run: `docker/build.sh && tests/test-image.sh` (no docker daemon in the sandbox).
