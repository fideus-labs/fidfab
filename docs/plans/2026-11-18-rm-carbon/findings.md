# Findings

- The Carbon reviews were two components, `carbon-review.fabro` and
  `carbon-security-review.fabro`, each a Fabro-native Gemini 4 Carbon `review` node followed by
  a Claude (opus) `address` node. `small`, `medium` and `verify` imported both; `large` imported
  neither but carried the vendored copies like every workflow directory.
- They owned four prompts: `review-carbon.md`, `address-carbon.md`, `security-review-carbon.md`,
  `address-carbon-security.md`. Two other prompts mentioned them: `address-claude.md` (pointed at
  `carbon-review-response.md`) and `pull-request.md` (lists the review stages that ran).
- The two Carbon `review` nodes were the only Fabro-native agent nodes in the repository. Every
  agent node is now an ACP node (Claude Code or Codex), so no stage of any workflow calls Gemini.
  `[run.model]` still names `vertex-gemini-3.8-flash`, as it named DeepSeek before the Carbon
  reviews existed. Not checked here: whether a run still needs the LiteLLM proxy to be up.
- Left in place, for a follow-up decision: `gemini-4-carbon` in `docker/litellm/config.yaml`,
  the `vertex-gemini-4-carbon` catalog row and its checks in `scripts/setup.sh`, the request to
  it in `scripts/litellm-proxy.sh test`, and the cases in `tests/test-setup.sh` that use it as
  the second model. Nothing uses the model now, yet `litellm-proxy.sh test` still fails for a
  project without Carbon access (Google restricts it to verified enterprise customers). Removing
  it means reworking the per-model cases in `tests/test-setup.sh` around a single model.
- The image does not ship `fabro`. `tests/validate-workflows.sh` needs it: install with
  `curl -fsSL https://fabro.sh/install.sh | sh`, then `fabro upgrade --prerelease` as CI does
  (the installer alone gave 0.254.0; the upgrade gave 0.415.0-nightly.0, which the checks ran on).
- `scripts/render-graphs.sh` works in the sandbox with a throwaway server. Under a scratch
  `HOME`, run `fabro install --no-upgrade-check --non-interactive --skip-llm --github-strategy
  token --github-username x` with `GH_TOKEN` set to a placeholder, append the
  `[llm.providers.litellm]` block from `scripts/setup.sh` to its `settings.toml`, set a
  placeholder `LITELLM_API_KEY` with `fabro secret set`, and `fabro server restart`. Rendering
  the unchanged graphs this way reproduced the committed SVGs byte for byte. Stop the server and
  delete the scratch `HOME` afterwards.
- Do not list processes with their command lines in the sandbox (`pgrep -af`, `ps -ef`): the
  sandbox driver's command line carries the run's environment, credentials included. Match on
  the process name instead (`pgrep -x fabro`).
