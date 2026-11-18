# Findings

- Fabro commits a checkpoint on `fabro/run/<id>` after every node
  (`fabro(<id>): <node> (<status>)`). The checkpoint holds whatever the stage left
  uncommitted, so in a past run (PR #15) the `implement` and `*.address` checkpoints carried
  all the work, most other checkpoints were empty, and the commit stage could only add an
  empty summary commit because the checkpoints were already on the remote.
- "When pushing is configured, Fabro pushes `fabro/run/{run_id}` after each checkpoint and
  again before successful completion" (docs.fabro.sh, execution/checkpoints).
  `[run.run_branch]` takes `enabled` and `push`; with `push = false` "Fabro creates local
  checkpoint commits but does not push" (execution/run-configuration). Pushing is the default.
- `fabro validate` (0.415.0-nightly.0) parses the table: a misspelled key or a non-boolean
  value is an error. It warns that the standalone runner ignores it, as it does for
  `[run.integrations]`. It also checks the prompt templates: syntax, `{% include %}` targets
  and unbound inputs.
- The setting reaches the server. On a Fabro server started inside the sandbox, a run created
  with `fabro create small` (never started, removed afterwards) showed
  `run.run_branch = {enabled: true, push: false}` in `fabro inspect --json`
  (`.[0].run_spec.settings.run.run_branch`); the same workflow without the table showed
  `push: true`, the default. Not verified: a complete run, which needs Docker and the agents.
- Cost of `push = false`: rewind and fork fetch the published run branch and "require
  run-branch pushes to be enabled and the commit to be available on origin". Resume resets
  the surviving workspace to its checkpoint and is not affected.
- The pull request branch is the run branch: the pull-request stage runs
  `git push -u origin HEAD` with HEAD on `fabro/run/<id>`. With `push = false` that is the
  first push, and it still carries the checkpoint commits made so far; the steward's pushes
  add more. Hence the rewrite comes last, and Fabro's own pushes must be off: the checkpoint
  of the rewrite stage itself would otherwise land on top of the clean history.
- Side effect on the steward gate: its approve step promises that the drafted commits are
  "not pushed yet", but by the documentation above Fabro pushed the branch after the draft
  stage's checkpoint. With `push = false` the promise holds. `fidfab-pr-reply --preview` now
  also lists the local checkpoint commits under "Unpushed commits"; they are pushed on
  approval and removed by the rewrite. Inferred from the documentation, not observed.
- Fidelity: the default (`compact`) preamble includes the scripts earlier stages ran and
  their output, so an agent after the steward would be shown `fidfab-pr-status` listings,
  including ones a human rejected. `truncate` passes "only the goal and run ID"; the rewrite
  node uses it, as the steward's agents do.
- The rewrite keeps the merge base (`git rebase -i --keep-base`, or `git reset --soft` to the
  merge base) instead of moving onto the tip of the base branch, so the tree stays identical
  to what was reviewed and tested.
- The stage starts from the pull request branch (`git fetch`, `git reset --hard @{u}`), not
  from the sandbox's HEAD. A checkpoint commits whatever a stage left in the tree, for
  example a PR body file, and with `push = false` such a commit stays local unless a later
  stage pushes. Starting from `@{u}` keeps it out, takes in commits someone else pushed, lets
  a retried attempt start clean, and makes the check direct: `git diff --quiet @{u} HEAD`
  before the push.
- After a `git fetch`, `git push --force-with-lease` alone overwrites commits that were
  fetched but are not in the local branch (the lease compares with the remote-tracking ref,
  which the fetch just moved). `--force-if-includes` refuses that push. The prompt uses both
  and the lint requires both. The steward's rebase step still uses the lease alone.
- Rehearsed with git 2.53.0 in a scratch repository: a stray unpushed file and a commit by
  someone else, the reset to `@{u}`, both ways of rebuilding the commits with an identical
  tree, an interrupted attempt followed by a restart, the push with both options, and the
  rejections (`stale info`, `remote ref updated since checkout`).
- The steward's `done` has three entries: `status` says `done` (green and quiet), `status`
  says `no-pr`, and a failed reply preview, which leaves threads awaiting replies. The
  component therefore starts with a script node, `fidfab-pr-status | tail -n 1` under
  `bash -o pipefail`, and the agent runs only on its `done` label. The tail keeps only the
  routing line, not the listing before it, which can quote threads. pipefail lets a failed
  status call fail the node, so it is retried and then takes the failure edge past the
  rewrite.
- `GIT_EDITOR=true` in the sandbox: a `squash` in a scripted todo list keeps the folded
  messages, checkpoint subject and `Fabro-*` trailers included, in the body (rehearsed with
  git 2.53); `fixup` drops them. The prompt asks for `fixup` with
  `exec git commit --amend -F <file>`, and checks the message bodies, not only the subjects.
  The todo list in git 2.53 reads `pick <hash> # <subject>`, so the prompt passes a whole
  todo file (`GIT_SEQUENCE_EDITOR="cp <file>"`) instead of editing it with a pattern.
- With `push = false` nothing reaches GitHub until the pull request stage pushes. Resume
  "requires the original workspace to survive" (docs.fabro.sh, execution/checkpoints), and
  the `fidfab` environment is `preserve = false`, so a run that fails earlier is lost unless
  it was started with `--preserve-sandbox`; `fabro retry` starts it again from the beginning.
- The force-push starts CI again on the same content and, where branch protection dismisses
  stale approvals, drops approvals. Nothing watches that CI run: the steward has finished.
- `tests/check-history-rewrite.sh` is run by `tests/validate-workflows.sh`, which CI already
  runs. `.github/workflows/ci.yml` is unchanged: the run's push token lacks the `workflow`
  scope (see PR #15), so `validate-workflows.sh` also runs `tests/test-history-rewrite.sh`
  and `tests/test-rewrite-push.sh`.
- Graphs: `fabro graph` needs a server with a ready LLM provider. In the sandbox:
  `fabro install --non-interactive --skip-llm --github-strategy token --github-username <login>`,
  a placeholder `LITELLM_API_KEY` secret, `scripts/setup.sh litellm`, then
  `scripts/render-graphs.sh`; `fabro server stop` afterwards (`fabro server start` to render
  again). The render is reproducible and uses the same bundled graphviz as before.
- In the sandbox, the command line of the sandbox driver process contains the run's
  credentials. Do not print full command lines (`ps -ef`, `pgrep -a`, `/proc/*/cmdline`);
  check a server with its own status command instead.
