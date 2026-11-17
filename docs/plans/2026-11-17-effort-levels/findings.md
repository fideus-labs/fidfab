# Findings

- Claude and Codex stages get their effort from `--effort` on `acp.command`
  (`fidfab-claude-acp` exports `CLAUDE_CODE_EFFORT_LEVEL`; `fidfab-codex-acp` puts
  `model_reasoning_effort` in `CODEX_CONFIG`). Before this change only three nodes set it
  (`large` draft `max`, `large` critique `xhigh`, personal-data `decide` `medium`); every
  other node inherited the agent default (Codex: `high` from `docker/config/codex-config.toml`).
- Claude Code 2.1.326 in the image accepts `low, medium, high, xhigh, max` (`claude --help`).
- Gemini nodes are Fabro-native. Fabro takes `reasoning_effort` as a node attribute / model
  stylesheet property, and `[run.model.controls] reasoning_effort` in `workflow.toml` for the
  run default (docs.fabro.sh: tutorials/multi-model, execution/run-configuration).
- Fabro requests `reasoning_effort` only "when the selected model allows it" (run-configuration
  docs), and the catalog rows `scripts/setup.sh litellm` wrote declared only `text` and `tools`.
  The rows now declare `reasoning_effort = { low, medium, high }` and
  `protocol_options = { reasoning_effort_levels = true }`. `setup.sh` never rewrites an existing
  `[llm.providers.litellm]` block, so a host set up earlier must add the two keys by hand; the
  step warns when they are missing. `fabro validate` does not consult the catalog, so nothing
  offline shows whether the effort reaches Gemini: check one run's request on a live server.
- Classification used (the task names categories, not nodes). Review, `high`: CodeRabbit
  `review` and `fallback`, Codex `review`, Claude `review`, security `review`, personal-data
  `audit`, `large` `critique`. Implementation, `xhigh`: `implement` in `small` and `medium`.
  Everything else `medium`, which lowers the `large` roadmap `draft` from `max` and its Codex
  `critique` from `xhigh`, and the baked Codex default from `high`.
- `tests/test-effort-levels.sh` derives the expected level from agent + class role word (Claude
  review fix); a node without an explicit effort, or without a role word, fails it.
