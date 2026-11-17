# Findings

- The Codex model is chosen in two places: the `luna` alias in
  `docker/rootfs/usr/local/bin/fidfab-codex-acp` (what every workflow stage uses) and the
  `model =` default in `docker/config/codex-config.toml` (interactive `codex` in the sandbox).
- Terra model ID: `gpt-6.1-terra`. It is the same generation as the previous `gpt-5.6-luna`
  and appears in the model list of the installed Codex CLI (0.169.0), which also lists
  `gpt-6.1-terra`. The task did not name a generation, so the 5.6 generation was kept; pin a
  different ID with `FIDFAB_MODEL_TERRA` in `[run.environment.env]` or change the default.
- The alias and the override variable were renamed, not aliased: `--model luna` and
  `FIDFAB_MODEL_LUNA` are no longer recognised. The wrapper passes unknown names through as
  literal model IDs, so a workflow newer than the image (or the reverse) sends `terra` / `luna`
  to Codex verbatim and the stage fails. Rebuild the image together with this change.
- Nothing in the repository set `FIDFAB_MODEL_LUNA`; only `tests/test-image.sh` forwarded it.
- `docs/graphs/large.svg` was edited by hand (class and label text) because
  `scripts/render-graphs.sh` needs `fabro` and a ready LLM provider. Node geometry is unchanged;
  re-render when convenient.
- `fabro` is not installed in the sandbox image, so `tests/validate-workflows.sh` cannot run here.
