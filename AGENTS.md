# fidfab — agent instructions

You are working in the fidfab repository: Fabro workflow components, prompts,
a Docker sandbox image and tests. Keep the following in mind.

## Layout

- `components/*.fabro` — reusable Fabro subgraphs (import=…). `components/prompts/` holds the
  prompts; `partials/` are included with `{% include "partials/<name>.md" %}`.
- `.fabro/workflows/<name>/` — runnable workflows (`workflow.toml` + `workflow.fabro`) and a
  generated copy of `components/`. Never edit the copies: change `components/` and run
  `scripts/sync-components.sh`.
- `docker/` — Dockerfile, agent configs, and `rootfs/usr/local/bin/fidfab-*` helpers that run
  inside the sandbox.
- `tests/` — shell tests that run inside the image (`tests/test-image.sh` drives them) and
  `validate-workflows.sh` for offline validation.
- `scripts/` — host-side setup, component sync, graph rendering.

## Verification

- `tests/validate-workflows.sh` must pass after any change to a `.fabro` or `workflow.toml`.
- `scripts/sync-components.sh --check` must pass.
- `tests/test-effort-levels.sh` must pass after any change to an agent node. Every Claude Code,
  Codex and Gemini node sets its effort explicitly: Claude implementation and planning `xhigh`,
  Claude and Codex review and security `high`, everything else `medium`. The test derives the
  level from the agent and the role word in the node's `class` (`implement`, `review`,
  `security`, `verify`, `plan`, `git`, `decision`), so every agent node carries exactly one; a
  node whose class does not decide its level goes in the test's `override` table, as the verify
  and address nodes of the Claude and Codex reviews do (`xhigh`).
- `tests/test-logical-commits.sh` must pass after any change to `logical-commits.fabro`, its
  prompt, `fidfab-history-tree` or a workflow graph (`validate-workflows.sh` runs it too). A workflow that imports
  `pr-steward.fabro` imports `logical-commits.fabro` as the steward's only successor.
- `tests/test-bootstrap.sh` must pass after any change to `fidfab-bootstrap`.
- `tests/test-build.sh` must pass after any change to `docker/build.sh`.
- `tests/test-model-aliases.sh` must pass after any change to a `.fabro`, a `fidfab-*-acp`
  wrapper or `tests/check-model-aliases.sh` (`validate-workflows.sh` runs the check too).
  Workflows pass model aliases (`--model terra`), never literal IDs; exact IDs are pinned with
  `FIDFAB_MODEL_*` in `[run.environment.env]`.
- `tests/test-codex-model.sh` must pass after any change to `fidfab-codex-acp` or
  `docker/config/codex-config.toml`.
- `tests/test-pr-steward.sh` must pass after any change to `fidfab-pr-status`,
  `fidfab-pr-reply` or `quote.jq`.
- `tests/test-review-wrappers.sh` must pass after any change to `fidfab-codex-acp`,
  `fidfab-coderabbit` or the credential step of `fidfab-bootstrap`.
- Every workflow graph sets `on_failure="exit"` (`validate-workflows.sh` checks it).
- `shellcheck -S warning` on all shell scripts; `node --check tests/acp-smoke.mjs`.
- If `docker` is available, `docker/build.sh && tests/test-image.sh` is the full check.

## Fabro constraints we have learned (keep the workflows valid)

- Node shapes: `Mdiamond` start, `Msquare` exit, `hexagon` human gate, `insulator` wait,
  `diamond` conditional, `script=` command node, `backend="acp"` + `acp.command=` for
  Claude Code / Codex. Use `output_schema="routing"` on nodes that pick the next edge.
- Every node with labelled (conditional) edges needs one unlabelled fallback edge.
- A failed node hands on to its unconditional edge unless `on_failure` says otherwise. The
  graph-level `on_failure="exit"` reaches imported nodes too (imports are merged at parse time;
  checked with a probe run on 2026-11-23), and an explicit `condition="outcome=failed"` edge
  still wins: a stage meant to go on after a failure needs one.
- Fabro authenticates an ACP agent whose `initialize` lists `authMethods`, and only with an
  `api-key` method. codex-acp always lists one, so `fidfab-codex-acp` empties the list when
  `auth.json` exists (a ChatGPT login, or an API key in it); Claude's adapter lists none.
- A usage limit (Claude, Codex, CodeRabbit) is a failed node like any other: Fabro does not
  classify ACP failures, and its retries wait at most 60 s. A run keeps the secrets it started
  with (`resume` too); another account takes `fabro secret set` and `fabro fork`, whose fresh
  sandbox the wrappers re-credential from the environment.
- An imported component's `exit` must have exactly one predecessor; funnel through a
  `done` diamond.
- `@prompt` paths inside components are resolved relative to the importing workflow
  directory and must not use `..`. Only single-level imports work (nested imports
  mis-prefix prompt paths).
- `{{ secrets.* }}` is only valid inside `[run.environment.env]`; `{{ env.* }}` is not supported.
- Human gate free text appears to downstream nodes as `human.gate.text`.
  A script node can capture it with `stdin_source="human.gate.text"`.
- `-I key=false` arrives as a boolean, not the string `"false"` the `[run.inputs]` default may
  be; compare with `inputs.key|string == "false"` in prompt conditionals.
- Prompts and `script=` are rendered once, when the run is created, from `goal`, `inputs` and
  `vars` only (`script=` takes plain `{{ inputs.NAME }}` substitution, shell-quoted). Anything
  known only inside the sandbox, such as the plan slug derived from the branch, is recorded by
  `fidfab-bootstrap` in `.fidfab/run.env` and read by later stages as `$FIDFAB_*`.
- In the sandbox HEAD is `fabro/run/<id>`. The branch the run started from exists as a local
  branch, but only the HEAD reflog (`checkout: moving from <branch> to fabro/run/<id>`) says
  which one it is; Fabro exports no variable for it.
- Each stage's environment carries Fabro's own github.com credential helper (`GIT_CONFIG_COUNT`:
  an empty `credential.https://github.com.helper` that clears the gh helper `fidfab-bootstrap`
  sets up, then a `credential-store` file that can be empty). No config file can win against
  that, so the Dockerfile appends gh through `GIT_CONFIG_PARAMETERS`; `tests/test-tools.sh`
  checks it.
- Fabro commits a checkpoint after every node (`fabro(<run id>): <node> (<status>)`, empty
  when the node changed nothing) and pushes `fabro/run/<id>` each time, without updating
  `origin/<branch>` in the sandbox: `git fetch` before comparing with the remote. No node
  attribute turns this off (`[run.run_branch] push` is run-wide), so a stage that rewrites
  history must force-push it, and the nodes after it still add their checkpoints.
- Edge conditions can read the run context (`condition="context.KEY=value"`). The
  `context_updates` of a routing node are run-wide: a later imported component sees the latest
  value, and a missing key takes the unconditional edge. `logical-commits.fabro` routes on
  `context.pr_status`, which `fidfab-pr-status` sets to its label. Script nodes cannot read
  the context, so `fidfab-pr-status` also writes the head it checked to
  `.fidfab/reviews/pr-head` for `fidfab-history-tree record`.
- `[environments.*]` tables in `workflow.toml` only serve `fabro validate`; they are not sent to
  the server, and `fabro run` ignores `[run.environment] id` (Fabro 0.396). The environment must
  be in the server catalog (`scripts/setup.sh environment`) and selected with
  `--environment fidfab`, else runs silently use `default` (`buildpack-deps:noble`).
  `[run.environment.image]` is not honoured as a run-level override; `resources` and `lifecycle` are.

## Style

- Commit messages: imperative subject under 72 characters, body explains why.
- No emojis. Plain Markdown. Do not add dependencies to the image without a comment
  explaining what uses them.
- Copyright Fideus Labs LLC, MIT licensed.
