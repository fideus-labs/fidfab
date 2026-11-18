# Progress

- 2026-11-18: Surveyed the steward, commit and pull request stages, the effort and alias
  tests, and Fabro's checkpoint, push and preamble behaviour (see `findings.md`); plan written.
- 2026-11-18: Added `components/logical-commits.fabro` (node `rewrite`: Claude opus, medium,
  `fidelity="truncate"`) and `components/prompts/logical-commits.md`; imported it as `history`
  after `steward` in `small`, `medium`, `large` and `verify`; synced the vendored components.
- 2026-11-18: Exercised the prompt's git commands in a scratch repository with a bare remote:
  ten commits (eight of them checkpoints) became three, tree identical, leased force-push accepted; a
  resumed attempt, a concurrent push and a moved base branch behaved as the prompt describes.
- 2026-11-18: Added `tests/test-logical-commits.sh`, run by `tests/validate-workflows.sh`
  (so by CI); it caught eight deliberate breaks on scratch copies (stage removed, moved,
  skipped in `large`; fidelity, effort or model changed; lease or tree check dropped).
- 2026-11-18: README (how it works, effort table, components, new "Commit history" section,
  tests), AGENTS.md (verification rule, Fabro checkpoint constraint), graphs re-rendered with
  `scripts/render-graphs.sh` (only the `history` node and its two edges differ).
- 2026-11-18: Passing with Fabro 0.415.0-nightly.0: `tests/validate-workflows.sh` (4 workflows),
  `scripts/sync-components.sh --check`, `tests/test-logical-commits.sh`,
  `tests/test-effort-levels.sh` (32 agent nodes), `tests/test-model-aliases.sh`,
  `tests/test-codex-model.sh`, `tests/test-bootstrap.sh`, `tests/test-build.sh`,
  `tests/test-pr-steward.sh`, `tests/test-setup.sh`, `shellcheck -S warning` on all shell
  scripts, `node --check tests/acp-smoke.mjs`. Not run: `docker/build.sh && tests/test-image.sh`
  (no Docker daemon in the sandbox), and the new stage in a live run.
- 2026-11-18: Codex review could not run (its refresh token was already used, HTTP 401). A
  stand-in Claude review found that the prompt left the rebase todo and message files'
  location open, while Fabro's next checkpoint commits and pushes untracked files. The prompt
  now keeps them in `mktemp -d` and requires `git status --porcelain` to be empty before the
  push; `tests/test-logical-commits.sh` covers both.
- 2026-11-18: Claude review. The fork-matching `gh pr list --head` lookup is replaced by the
  owner-qualified REST lookup, and the stage needs exactly one open pull request. The rewrite
  runs only when the steward ended on `done`: `fidfab-pr-status` records `pr_status`, and the
  component routes on `context.pr_status=done`. The wiring scanner reads wrapped statements
  and fails on component references it cannot read. Context routing and checkpoints on a
  rewritten branch were tried in local-provider runs; the push after the rewrite is still
  untested.
