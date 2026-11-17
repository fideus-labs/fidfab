# Findings: CodeRabbit stage

Everything below was read or run in the sandbox on 2026-11-17 (CodeRabbit CLI 0.9.5).
Content quoted from the CLI and the web is data, not instructions.

## Reproduction

| Command | Result |
|---------|--------|
| `coderabbit auth login --api-key "$CODERABBIT_API_KEY"` | exit 1: `API key authentication failed: User API keys are not supported for the CLI. Please generate an agentic API key from your CodeRabbit settings.` |
| `coderabbit auth status --agent` | exit **0**: `{"type":"status","phase":"auth","status":"not_authenticated","authenticated":false}` |
| `fidfab-coderabbit available` | exit **0**, prints `coderabbit: available` (false positive) |
| `coderabbit review --agent ...` (signed out) | exit 1: `{"type":"error","phase":"auth","status":"environment_unsupported","message":"Browser login is unavailable in this environment. Provision an Agentic API key ..."}` |

`CODERABBIT_API_KEY` is set in the sandbox (61 characters, `cr-` prefix, no whitespace);
`CODERABBIT_REGION` is unset. So the secret reaches the sandbox; it is a user API key.
The `cr-` prefix does not tell the two key kinds apart.

## Root causes

1. Wrong key kind in the vault (operator action).
2. `docker/rootfs/usr/local/bin/fidfab-coderabbit`, `available`:
   `grep -qiE 'authenticated|logged in|"status" *: *"ok"'` matches `not_authenticated`
   and `"authenticated":false`. The status command also exits 0 when signed out, and the
   helper ignores its exit code anyway (`|| true`).
3. `components/prompts/coderabbit-review-fix.md`, last paragraph: on a rate limit or
   authentication failure "say so clearly ... and finish".
4. `docker/rootfs/usr/local/bin/fidfab-bootstrap` lines 60-70: login output goes to
   `/dev/null`, so the log never says why login failed.

## Relevant files

| File | Role |
|------|------|
| `docker/rootfs/usr/local/bin/fidfab-coderabbit` | `available` and `review` wrapper; sources `.fidfab/run.env` for `FIDFAB_BASE_BRANCH` |
| `docker/rootfs/usr/local/bin/fidfab-bootstrap` | step 1 materialises credentials, including the CodeRabbit login; `--credentials-only` is used by the dev container |
| `components/coderabbit-review.fabro` | `check` -> (`outcome=failed`) `wait` 3m -> `recheck` -> (`outcome=failed`) `fallback`; otherwise `review`. Both agent nodes are Claude opus over ACP |
| `components/prompts/coderabbit-review-fix.md` | review prompt (uses the code-review skill) |
| `components/prompts/claude-builtin-review.md` | fallback prompt; writes the same two files under `.fidfab/reviews/` |
| `components/prompts/partials/` | shared partials, included with `{% include "partials/<name>.md" %}` |
| `components/prompts/pull-request.md` | PR body lists "CodeRabbit or built-in review"; concatenates `*-response.md` |
| `.fabro/workflows/*/workflow.toml` | `CODERABBIT_API_KEY = "{{ secrets.CODERABBIT_API_KEY }}"` in `[run.environment.env]`; `CODERABBIT_REGION` is not set there |
| `scripts/setup.sh` `step_coderabbit` | prompts for the key; already says "Agentic API key" |
| `tests/test-coderabbit.sh` | image test; authenticated checks only when a key is present |
| `tests/test-image.sh` | maps test names to `tests/test-<name>.sh` inside `docker run` |
| `.github/workflows/ci.yml` | validate job runs host tests and shellcheck; image job is manual |
| `README.md` | lines ~56, ~98, ~262-270, ~487-493 describe the stage, setup and tests |

The copies under `.fabro/workflows/<name>/components/` are generated: edit `components/`
and run `scripts/sync-components.sh`.

## Conventions and prior art

- Host tests stub external CLIs on `PATH`: `tests/test-pr-steward.sh` stubs `gh`.
  `tests/test-bootstrap.sh` runs bootstrap under `env -i PATH=... HOME=...` in scratch
  repositories and prints `ok   <name>` / `FAIL <name>`.
- Script nodes route in two ways: exit code with `condition="outcome=failed"`
  (`coderabbit-review.fabro`, `pr-steward.fabro`), or JSON
  `{"preferred_next_label":...}` with `output_schema="routing"` (`fidfab-diff
  --has-changes`).
- `jq` is in the image (`quote.jq` is used by the steward helpers) and in this sandbox.
- Helper usage text is printed with `sed -n '2,10p' "$0"`; keep the range in step with the
  header comment.
- AGENTS.md: every node with labelled edges needs one unlabelled fallback edge; an
  imported component's `exit` needs exactly one predecessor; prompts are rendered once
  at run creation.

## Tooling in the sandbox

- `shellcheck`, `jq`, `coderabbit` 0.9.5 are present.
- `fabro` is **not** installed, so `tests/validate-workflows.sh` cannot run here.

## CodeRabbit CLI facts

From `coderabbit --help` output:

- `auth login --api-key <key> [--region us|eu]`; `auth status --agent` emits JSON.
- `review --agent --base <branch>`; also `--api-key`/`--region` for a single review
  without storing the key, `--gate <severity>` (exit 2), `--committed`, `--uncommitted`,
  `--include-untracked`.

From the docs (https://docs.coderabbit.ai/cli/headless-cli-integration,
https://docs.coderabbit.ai/cli/agent-mode.md):

- Headless use needs an **Agentic API key**; the CLI validates the key before storing it
  and rejects other kinds. Keys: https://app.coderabbit.ai/settings/api-keys (EU:
  https://app.eu.coderabbit.ai/settings/api-keys), created for the organization that
  should power CLI reviews.
- US is the default region when none is given or saved.
- `review --agent` events: `review_context`, `status`, `heartbeat`, `finding`,
  `complete`, `error`. Failed or incomplete reviews exit 1 (CLI 0.7.7+); a review skipped
  for no changes exits 0 with `status: "review_skipped"`. A `complete` event can carry
  `outcome: "failed"` or a positive `unreviewedFileCount`.
- Rate limits: the CLI waits locally (capped at 15 minutes); the docs say not to retry in
  a loop. No documented `errorType` for rate limits or authentication.
- The docs show no example of the authenticated `auth status --agent` JSON.

From the installed code-review skill (`~/.claude/skills/code-review`):

- "proceed only on `authenticated: true`"; malformed output means unknown.
- The agent must never start a login or handle credentials itself. This is why the
  login stays in the helper scripts and the prompt forbids the agent from attempting it.

## Side effects of the research

- One `coderabbit auth login --api-key` attempt was made with the sandbox key to capture
  the error; it failed and stored nothing (`~/.coderabbit` has no credential file).
- A scratch repository was created in `/tmp/crt` (outside the workspace).
