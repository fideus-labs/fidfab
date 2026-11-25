# Setup

How to set up a workstation to run fidfab workflows. The prerequisites are listed in the
[README](../README.md).

## Guided setup

```bash
git clone https://github.com/fideus-labs/fidfab.git
cd fidfab
scripts/setup.sh            # all steps, interactive
scripts/setup.sh litellm    # or one step at a time
```

The script does not create or start the LiteLLM proxy, which needs your Google Cloud project
and service-account key. Run the `scripts/litellm-proxy.sh` commands from step 2 below before
the guided setup (or rerun `scripts/setup.sh litellm` afterwards); otherwise the `litellm` step
only reports the proxy as missing and its model tests fail.

The steps below are what the script does, if you prefer to run them yourself.

## 1. Install Fabro and upgrade to the latest pre-release

```bash
curl -fsSL https://fabro.sh/install.sh | bash
export PATH="$HOME/.fabro/bin:$PATH"
fabro upgrade --prerelease
fabro install --non-interactive --skip-llm --github-strategy token \
  --github-username "$(gh api user --jq .login)"   # GitHub token from gh, no LLM provider yet
fabro server start
```

The installer and the `--prerelease` upgrade channel are documented in the
[Fabro quick start](https://docs.fabro.sh/getting-started/quick-start). The scripted flags are
hidden from `fabro install --help`. The interactive wizard (`fabro install`) works too: answer No
to `Configure LLM providers now?`. When `codex` is on PATH it otherwise asks
`OpenAI (Codex) detected. Set up OpenAI with device code login?`, which stores a
ChatGPT-subscription credential that Fabro routes through the Codex backend
(`chatgpt.com/backend-api/codex`). fidfab does not use Fabro's OpenAI provider: native nodes run
on Gemini through LiteLLM (next step) and the Codex stages authenticate with `CODEX_AUTH_JSON_B64`
(step 5).

That GitHub token is your `gh` login, with `repo` scope on every repository you can reach, and
every agent in every run can use it; the `permissions` table in `workflow.toml` does not limit
it. Switch Fabro to a GitHub App, which gives each run a one-hour token limited to its
repository and the workflow's permissions: `scripts/setup.sh github-app`, then the steps it
prints ([github-token.md](github-token.md)). It registers a new App, or takes one the
organization already has.

`scripts/setup.sh author` then makes run commits carry your own identity instead of the GitHub
token's login (or the App's bot) and noreply address: it appends
[`[run.git.author]`](https://docs.fabro.sh/administration/server-configuration#run-git-author-section)
with `git config user.name` and `user.email` to `~/.fabro/settings.toml` and restarts the server.
Fabro injects them as `GIT_AUTHOR_*` and `GIT_COMMITTER_*` into every run. An existing block is
kept, without a restart; the step warns when it no longer matches `git config`. `fabro run` then
warns that `settings.toml` contains `run`: keep the block ([limitations.md](limitations.md)).

```toml
[run.git.author]
name = "Your Name"
email = "you@example.com"
```

## 2. Gemini on Vertex AI through LiteLLM

Fabro's native nodes call Gemini on Vertex AI through a local
[LiteLLM](https://docs.litellm.ai/) proxy, using Fabro's built-in
[LiteLLM provider](https://docs.fabro.sh/integrations/litellm). Create the Google Cloud project,
the least-privilege service account, and its key first
([vertex-ai-litellm.md](vertex-ai-litellm.md)), then:

```bash
scripts/litellm-proxy.sh init PROJECT_ID   # ~/.config/fidfab-litellm/proxy.env with a new master key
scripts/litellm-proxy.sh start             # pinned LiteLLM image on 127.0.0.1:4000
scripts/litellm-proxy.sh test              # one request to each model
scripts/setup.sh litellm                   # Fabro provider block, LITELLM_API_KEY, model tests
```

`scripts/litellm-proxy.sh test` exits nonzero if either model fails. Fix a Gemini 3.8 Flash
failure before you continue. If only Gemini 4 Carbon fails (for example, the project has no
access to it), you can continue: no shipped workflow uses it.

The step adds `[llm.providers.litellm]` with the models `vertex-gemini-3.8-flash` and
`vertex-gemini-4-carbon` to `~/.fabro/settings.toml`, stores the proxy master key as the
`LITELLM_API_KEY` vault secret, restarts the server, and runs
`fabro model test --model <id> --tools` for both. The workflows choose Gemini 3.8 Flash in their
`workflow.toml` `[run.model]`. No workflow uses Gemini 4 Carbon; a native node can select it
with `provider="litellm", model="vertex-gemini-4-carbon"`
([Fabro stylesheets and node attributes](https://docs.fabro.sh/workflows/stylesheets)). No
shipped workflow has a Fabro-native node. The Fabro server can still call Gemini 3.8 Flash, the
provider's `small_default` model, for metadata such as generated run titles
([Fabro models](https://docs.fabro.sh/core-concepts/models)), so keep the proxy running. The
Claude Code and Codex stages use your subscriptions.

## 3. Brave Search

```bash
fabro secret set BRAVE_SEARCH_API_KEY
```

Fabro's `web_search` tool uses Brave whenever this key is in the server vault; it is not read
from the environment ([Fabro Brave Search integration](https://docs.fabro.sh/integrations/brave-search)).

## 4. Build the sandbox image

```bash
docker/build.sh                                      # generic image
docker/build.sh https://github.com/OWNER/REPO main   # with a baked-in clone and warm caches
docker/build.sh git@github.com:OWNER/REPO main       # private repo, cloned with your ssh-agent
```

The image starts from `ubuntu:26.04` and installs, in this order:
[pixi](https://pixi.sh) (environments detached under `/opt/fidfab/cache/pixi-envs`),
Rust via rustup with `cargo-nextest`, `cargo-llvm-cov`, `cargo-deny`, `cargo-audit`,
`wasm-pack` and [sccache](https://github.com/mozilla/sccache) as `RUSTC_WRAPPER` (25 GB local
cache under `/opt/fidfab/cache/sccache`), [Vite+](https://vite.plus), Node 22, Claude Code,
Codex, the
[Claude Code ACP adapter](https://github.com/agentclientprotocol/claude-agent-acp) and the
[Codex ACP adapter](https://github.com/agentclientprotocol/codex-acp), the
[CodeRabbit CLI](https://docs.coderabbit.ai/cli/overview), [Serena](https://github.com/oraios/serena)
wired into Claude Code as an MCP server, [cocoindex-code](https://github.com/cocoindex-io/cocoindex-code)
wired into Codex as an MCP server, and the planning-with-files, CodeRabbit code-review and
Cloudflare security-audit skills for both agents. The `gh` and `docker` CLIs are present for the
PR stages. Pin versions with `CLAUDE_CODE_VERSION`, `CODEX_VERSION`, `RUST_TOOLCHAIN`, etc.

Claude Code and Codex default to `latest`, which Docker's layer cache freezes at whatever was
latest when the layer was built. So `build.sh` passes the version of `claude` and `codex` on
your machine as a floor (`>=2.1.325`): the layer is rebuilt whenever your version changes, and
the image gets `latest`, never anything older than what you run locally. Setting
`CLAUDE_CODE_VERSION` or `CODEX_VERSION` yourself turns this off for that agent.

With a repository URL, the build clones it to `/opt/fidfab/repo`, pre-builds its pixi and
Cargo dependencies (a Rust repository is built through sccache, so its cache is warm), and
`fidfab-bootstrap` reuses those caches in every run. Nothing secret is baked into the image.

Private repositories can be given as SSH URLs. `build.sh` then forwards your ssh-agent to the
clone step only (`docker build --ssh default`), so `ssh-add` your GitHub key first; the key never
reaches an image layer. GitHub's host keys, for `github.com` and the port-443 endpoint
`ssh.github.com`, are pinned in `docker/rootfs/etc/ssh/ssh_known_hosts`. The baked clone's
`origin` is rewritten to HTTPS on `github.com`, because sandboxes authenticate to GitHub with
Fabro's `GITHUB_TOKEN` rather than an SSH key.

If your git config rewrites the URL you give (`url.<base>.insteadOf`, commonly `git@github.com:`
to `https://github.com/`), `build.sh` clones the rewritten URL when it is plain HTTPS and reads without
credentials, as a public repository does, and keeps the SSH URL and your ssh-agent otherwise.

## 5. Agent credentials (Fabro vault)

Secrets live in the Fabro server vault and are injected into the sandbox as environment
variables by `[run.environment.env]` in each `workflow.toml`
([run configuration](https://docs.fabro.sh/execution/run-configuration)).

**Claude Code ACP**

```bash
claude setup-token                       # on the host, logs in with your Claude subscription
fabro secret set CLAUDE_CODE_OAUTH_TOKEN # paste the sk-ant-oat… token
```

`claude-agent-acp` honours Claude Code's environment, so the token and `ANTHROPIC_MODEL`
select the account and model. Set `FIDFAB_MODEL_OPUS` / `FIDFAB_MODEL_FABLE` in
`[run.environment.env]` to pin exact model IDs (defaults pass `opus` / `fable` through).
Workflows name aliases only (`tests/check-model-aliases.sh` rejects literal IDs); the
Codex `terra` alias is pinned the same way with `FIDFAB_MODEL_TERRA` (default
`gpt-6.1-terra`). The former `luna` alias was replaced by `terra`: `--model luna` now fails
with exit 64 and `FIDFAB_MODEL_LUNA` is ignored with a warning.

**OpenAI Codex ACP**

```bash
CODEX_HOME=~/.codex-fabro scripts/setup.sh --replace codex   # a ChatGPT login of Fabro's own (device code)
# by hand: CODEX_HOME=~/.codex-fabro codex login --device-auth
#          base64 -w0 ~/.codex-fabro/auth.json | fabro secret set --value-stdin CODEX_AUTH_JSON_B64
# or with an API key:
printf '{"OPENAI_API_KEY":"sk-…"}' | base64 -w0 | fabro secret set --value-stdin CODEX_AUTH_JSON_B64
```

`fidfab-bootstrap` writes this to `$CODEX_HOME/auth.json` inside the sandbox; `codex-acp`
reads the same auth store as the Codex CLI ([codex-acp](https://github.com/agentclientprotocol/codex-acp)).
After `fabro fork`, whose sandbox is new, `fidfab-codex-acp` writes it again when it is missing.
A ChatGPT login renews its tokens, and a renewal voids every other copy: give Fabro a login of
its own (`CODEX_HOME=~/.codex-fabro` above), not a copy of the one Codex uses on the host. When
the sandbox's Codex says "Your access token could not be refreshed", store a fresh one, then
start a new run or fork the stopped one: a run keeps the secrets it started with. Fabro
authenticates an ACP agent that advertises a sign-in method, by API key only; signed in through
`auth.json`, `fidfab-codex-acp` advertises none, as Claude's adapter does.
Subscription tokens rotate, so re-run this step if Codex stages stop authenticating.

**CodeRabbit CLI**

```bash
fabro secret set CODERABBIT_API_KEY      # agentic API key from the CodeRabbit dashboard
```

The sandbox runs `coderabbit auth login --api-key …` and then `coderabbit review --agent --base <branch>`
([CodeRabbit headless integration](https://docs.coderabbit.ai/cli/headless-cli-integration)).
`fidfab-coderabbit available` logs in again when the sandbox is not logged in, as after `fabro fork`.
Set `CODERABBIT_REGION=eu` in `[run.environment.env]` for EU accounts.

## 6. Verify the image

```bash
tests/test-image.sh                      # tools, coderabbit, claude-acp, codex-acp
CLAUDE_CODE_OAUTH_TOKEN=… CODEX_AUTH_JSON_B64=… CODERABBIT_API_KEY=… tests/test-image.sh
```

Without credentials the tests check installation and the ACP `initialize` handshake. With
credentials they run an authenticated `session/prompt` round-trip against each agent and
`coderabbit auth status`. If the image was built with `UBUNTU_VERSION=…`, run the tests with
the same variable set so the release check expects that version (release number or codename).

## 7. Register the environment and run the doctor

The workflows select the server-managed environment `fidfab` (`[run.environment] id` in each
`workflow.toml`). Fabro reads `[environments.*]` tables only from the server's
`~/.fabro/settings.toml`, never from a workflow, so this step is required:
`scripts/setup.sh environment` appends the table below and restarts the server, which moves it
into its persisted environment catalog (the block then disappears from `settings.toml`).

```toml
[environments.fidfab]
provider = "docker"

[environments.fidfab.image]
docker = "fidfab:latest"
```

Each run then has to select it with `--environment fidfab` (see [Running workflows](workflows.md#running-workflows)). Without
both, Fabro silently falls back to its `default` environment (`buildpack-deps:noble`) and the
first stage fails with `fidfab-bootstrap: command not found`.

```bash
fabro doctor
```

Expect green for the local server, LLM provider (litellm), GitHub token, Docker sandbox, and
Web Search (`brave: configured and reachable`).
