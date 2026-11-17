# Progress

- 2026-11-17: Surveyed effort settings; plan written.
- 2026-11-17: Set `--effort` on all 29 Claude/Codex nodes and `reasoning_effort` on the 2 Gemini
  nodes and in the four `workflow.toml`; Codex default to medium; synced components.
- 2026-11-17: Added `tests/test-effort-levels.sh` (CI, AGENTS.md), extended `tests/test-setup.sh`,
  declared the Gemini reasoning-effort capability in `scripts/setup.sh`; README and
  `docs/vertex-ai-litellm.md` updated.
- 2026-11-17: Passing: `tests/validate-workflows.sh` (4 workflows), `sync-components.sh --check`,
  `test-effort-levels.sh`, `test-setup.sh`, `test-bootstrap.sh`, `shellcheck -S warning`,
  `node --check tests/acp-smoke.mjs`. Not run: `docker/build.sh && tests/test-image.sh` (no docker daemon in the sandbox).
