# Known limitations

- The workflows are validated offline with `fabro validate` and the ACP handshake has been
  tested against the published adapters; end-to-end runs depend on your subscriptions and
  the first full image build on your machine.
- Fabro's standalone runner ignores `[run.integrations]`; the server-managed run path injects the
  GitHub token. Running under `fabro run` against a local server is the supported mode.
- Fabro resolves component prompt paths relative to the importing workflow, so components are
  vendored per workflow (`scripts/sync-components.sh`). Nested imports (a component importing
  a component) are avoided for the same reason.
- `fabro graph` needs a ready LLM provider on the server before it renders.
- The history rewrite cannot remove the checkpoint commits of the nodes that run after it: a
  rewritten pull request branch still ends with a few empty `fabro(...)` commits
  ([Commit history](workflows.md#commit-history)).
- The history rewrite has not run in a live Fabro run yet. A local run (Fabro 0.415) shows the
  next checkpoint committed on top of a rewritten branch, but local runs do not push, so it is
  not seen yet that Fabro's push after the stage is the plain fast-forward the stage relies on.
  If it is not, the code on GitHub is still the reviewed tree: the run ends as
  `publish_failed`, or the branch gets its checkpoint history back.
- `fabro run` ignores `[run.environment] id` in `workflow.toml` and uses the server's `default`
  environment unless `--environment fidfab` is passed (Fabro 0.396); an unknown id is not an
  error either. `fabro inspect <run>` shows the resolved image under `run.environment.image`.
- `fabro run` does not send `[run]` settings from `~/.fabro/settings.toml` to the server (Fabro
  0.415 warns about it), so the default model lives in each `workflow.toml` `[run.model]`. Remove
  any `[run.model]` left in `settings.toml` by the former DeepSeek setup step.
- If the install wizard set up OpenAI via Codex device login, that ChatGPT-subscription OpenAI
  credential stays unused; the workflows select the `litellm` provider explicitly.
- Vertex AI Standard pay-as-you-go capacity is shared; bursts can return `429`. LiteLLM retries,
  and Fabro retries the stage; a budget alert in Google Cloud Billing notifies but does not cap spend.
- Subscription credentials (Claude Code OAuth token, Codex `auth.json`) expire and rotate;
  `scripts/setup.sh codex` copies the current `auth.json` again; for Claude Code, run
  `fabro secret rm CLAUDE_CODE_OAUTH_TOKEN` first, then `scripts/setup.sh claude` (setup keeps
  a secret that is already set).
