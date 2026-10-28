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
- `shellcheck -S warning` on all shell scripts; `node --check tests/acp-smoke.mjs`.
- If `docker` is available, `docker/build.sh && tests/test-image.sh` is the full check.

## Fabro constraints we have learned (keep the workflows valid)

- Node shapes: `Mdiamond` start, `Msquare` exit, `hexagon` human gate, `insulator` wait,
  `diamond` conditional, `script=` command node, `backend="acp"` + `acp.command=` for
  Claude Code / Codex. Use `output_schema="routing"` on nodes that pick the next edge.
- Every node with labelled (conditional) edges needs one unlabelled fallback edge.
- An imported component's `exit` must have exactly one predecessor; funnel through a
  `done` diamond.
- `@prompt` paths inside components are resolved relative to the importing workflow
  directory and must not use `..`. Only single-level imports work (nested imports
  mis-prefix prompt paths).
- `{{ secrets.* }}` is only valid inside `[run.environment.env]`; `{{ env.* }}` is not supported.
- Human gate free text appears to downstream nodes as `human.gate.text`.
- `[environments.*]` tables in `workflow.toml` only serve `fabro validate`; they are not sent to
  the server, and `fabro run` ignores `[run.environment] id` (Fabro 0.396). The environment must
  be in the server catalog (`scripts/setup.sh environment`) and selected with
  `--environment fidfab`, else runs silently use `default` (`buildpack-deps:noble`).
  `[run.environment.image]` is not honoured as a run-level override; `resources` and `lifecycle` are.
- Fabro workers inherit the server's cwd. If the server was started from a directory that was
  later deleted (a removed worktree), every run fails within milliseconds with "Worker exited
  before emitting a terminal run event" and `~/.fabro/storage/logs/server.log` shows "Failed to
  get current directory". Check the server's cwd (`readlink /proc/<pid>/cwd` on Linux,
  `lsof -p <pid> -a -d cwd` on macOS; pid in `~/.fabro/storage/server.json`) and run
  `fabro server restart` from a stable directory.

## Style

- Commit messages: imperative subject under 72 characters, body explains why.
- No emojis. Plain Markdown. Do not add dependencies to the image without a comment
  explaining what uses them.
- Copyright Fideus Labs LLC, MIT licensed.
