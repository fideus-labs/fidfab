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
- The history rewrite cannot keep Fabro from committing and pushing the empty `fabro(...)`
  checkpoints of the nodes that run after it; only the workflows' `run_complete` hook
  (`fidfab-history-tree trim`) takes them off again. A rewritten pull request branch keeps
  them when the hook fails, with an image built before the helper had `trim`, and in a
  workflow of your own without the hook ([Commit history](workflows.md#commit-history)).
- The history rewrite has run in live runs (pull requests #28 and #31): Fabro committed and
  pushed the next checkpoints on top of the rewritten branch, which kept its rewritten
  commits. The `trim` hook has not run in a live run yet. Probe runs (Fabro 0.423) showed when
  and where a `run_complete` hook runs and that a failing one does not fail the run, but not
  this hook on a rewritten branch.
- `fabro run` ignores `[run.environment] id` in `workflow.toml` and uses the server's `default`
  environment unless `--environment fidfab` is passed (Fabro 0.396); an unknown id is not an
  error either. `fabro inspect <run>` shows the resolved image under `run.environment.image`.
- `fabro run` does not send `[run]` settings from `~/.fabro/settings.toml` to the server (Fabro
  0.415 warns about it), so the default model lives in each `workflow.toml` `[run.model]`. Remove
  any `[run.model]` left in `settings.toml` by the former DeepSeek setup step. The warning stays
  as long as the `[run.git.author]` block of `scripts/setup.sh author` is there, and that block
  must stay: a server on the same machine reads the file itself and applies it to every run
  (`fabro inspect <run>` shows it under `run.git.author`; seen with Fabro 0.423). It is one
  person's identity, so it does not belong in a checked-in `workflow.toml`.
- If the install wizard set up OpenAI via Codex device login, that ChatGPT-subscription OpenAI
  credential stays unused; the workflows select the `litellm` provider explicitly.
- Vertex AI Standard pay-as-you-go capacity is shared; bursts can return `429`. LiteLLM retries,
  and Fabro retries the stage; a budget alert in Google Cloud Billing notifies but does not cap spend.
- Subscription credentials (Claude Code OAuth token, Codex `auth.json`) expire and rotate;
  `scripts/setup.sh codex` copies the current `auth.json` again; for Claude Code, run
  `fabro secret rm CLAUDE_CODE_OAUTH_TOKEN` first, then `scripts/setup.sh claude` (setup keeps
  a secret that is already set).
