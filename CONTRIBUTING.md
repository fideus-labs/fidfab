# Contributing to fidfab

Thanks for helping build the factory. fidfab is small on purpose: a handful of
Fabro components, the prompts they run, a Docker image, and tests. Changes
should keep it readable by a research software engineer who has never used
Fabro.

## Ground rules

- Edit components and prompts under `components/` only. The copies under
  `.fabro/workflows/*/components/` are generated; run
  `scripts/sync-components.sh` and commit the result (CI checks with `--check`).
- Every workflow must pass `tests/validate-workflows.sh` (offline `fabro validate`).
- Shell scripts pass `shellcheck -S warning`; keep them `set -euo pipefail`.
- Nothing secret is ever written into the repository or the image. Credentials
  flow from the Fabro vault into the sandbox environment at run time.
- Prompts are plain Markdown with Fabro's `{% include "partials/…" %}` only.
  Keep the human-facing instructions (gates, plan reviews) short and specific.
- Re-render `docs/graphs/*.svg` with `scripts/render-graphs.sh` when a
  workflow graph changes.

## Development loop

```bash
scripts/setup.sh fabro            # Fabro + latest pre-release
docker/build.sh                   # image (slow the first time)
tests/test-image.sh               # tool, CodeRabbit, Claude ACP, Codex ACP tests
tests/validate-workflows.sh       # workflow validation
fabro run verify --goal "Verify the current branch" --target OWNER/REPO@branch
```

Use the `small` workflow on fidfab itself for non-trivial changes; it is the
dogfood path.

## Pull requests

- One topic per PR, with a descriptive title and a body that states what
  changed and why.
- Include validation output or test logs for Docker-affecting changes, since
  CI does not build the image on every PR (trigger the `image` job manually
  with "Run workflow" when needed).

By contributing you agree that your contributions are licensed under the MIT
License (see `LICENSE`).
