## Workspace conventions

- You are in a git checkout of the target repository inside a disposable fidfab sandbox.
  The branch under work is the current branch; the base branch, merge base and plan slug
  are in `.fidfab/run.env` (`FIDFAB_BASE_BRANCH`, `FIDFAB_MERGE_BASE`,
  `FIDFAB_PLAN_SLUG`) and set in your shell. Expand `$FIDFAB_PLAN_SLUG` wherever a path
  in the task uses it. If it is unset (an image older than the workflow, or a forked or
  rewound run), use the slug of the plan directory this task already has, or `task` when
  there is none.
- `fidfab-diff` prints the complete branch diff (merge base → working tree, including
  uncommitted and untracked files). `fidfab-diff --names` lists changed files. Use these
  instead of guessing the scope.
- Review artifacts live in `.fidfab/reviews/` (git-ignored). Planning artifacts live in
  the repository (see the task) so they travel with the pull request.
- Toolchains are preinstalled and warm: `pixi`, `cargo` (nextest, llvm-cov), `vp`
  (Vite+), `uv`, `gh`. Do not install tools over the network unless the repository's
  own instructions require it.
- Prefer the repository's documented commands (CLAUDE.md, AGENTS.md, CONTRIBUTING.md,
  pixi tasks, `cargo xtask`, package scripts) for building and testing.
- Never force-push, never rewrite history that is already on the remote except where a
  stage explicitly asks you to rebase, and never commit secrets.
- Finish your reply with a short markdown summary of what you did and what you verified.
