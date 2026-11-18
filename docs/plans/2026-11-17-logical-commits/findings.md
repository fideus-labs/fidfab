# Findings

## Why the stage is needed

- Fabro commits a checkpoint after every node, `fabro(<run id>): <node> (<status>)`, holding
  whatever the node changed (the commit is empty when it changed nothing), and pushes
  `fabro/run/<id>` each time (docs.fabro.sh: execution/checkpoints). In pull request #15 that
  was 32 checkpoint commits, six of which hold all the work (`implement` and five review
  fixes); the descriptive commit written by the commit stage was empty, because the
  checkpoints had already committed everything.

## Fabro behaviour the stage depends on

- The checkpoint push does not update `origin/<branch>` in the sandbox: in this run GitHub
  had the run branch at `HEAD` while `git branch -r` listed only `origin/main`. The prompt
  therefore fetches before it compares anything with the remote.
- The rewrite has to be force-pushed. Left local, Fabro's next checkpoint push would not be
  a fast-forward, and the docs say a failed final push marks the run `publish_failed` (read
  in the docs, not tried).
- Nodes that run after the rewrite still get checkpoint commits, and Fabro pushes them on top
  of the rewritten branch (`history.rewrite`, `history.done`, then the workflow's closing
  nodes). No node attribute turns this off. `[run.run_branch] push = false` is run-wide: only
  the stages' own pushes would reach GitHub, and GitHub-backed fork and rewind stop working.
  Not changed and not tried here.
- The default preamble (`fidelity="compact"`) gives a node the output of earlier command
  nodes, which includes the `fidfab-pr-status` listing with review comment text. The node
  runs with `fidelity="truncate"` (goal and run id only), like the steward's agents.
- A failed `rewrite` (default `on_failure="route"`) still takes its only edge, to `verify`.
  If it failed before pushing, GitHub keeps the history it had, and `verify` passes unless
  one of its other checks fails (HEAD left on another branch, a failed fetch). If it
  pushed a changed tree and then failed, the change is already on GitHub: `verify` finds the
  mismatch and stops at `alarm`.
- Edge conditions read the run context (`condition="context.pr_status=done"`). The
  `context_updates` of a routing script are run-wide, so a later imported component sees a key
  that the steward's `status` node set, with its latest value. A missing key takes the
  unconditional edge. Tried on a local server with the `local` provider (Fabro 0.415).
- After a node rewrites the branch (`git reset --soft` and `git commit`), Fabro commits the
  next checkpoint on top of the rewritten `HEAD` and records that SHA. Seen in a local-provider
  run (Fabro 0.415). Local runs do not push, so the push half (a plain fast-forward after the
  stage's own force-push) is still taken from the docs.

## Decisions

- The rewrite runs only when the steward loop ended on its last status check saying `done`.
  `fidfab-pr-status` records its label as `context.pr_status`, and a diamond in the component
  routes on it. The steward's other exits are `no-pr` and an incomplete reply preview. After
  the latter, the drafted commits a human has not approved are already on GitHub (checkpoint
  push), and a rewrite would fold them into the reviewed commits.
- Pull request lookup: `gh api "repos/{owner}/{repo}/pulls?head={owner}:<branch>&state=open"`.
  `gh pr list --head` also matches pull requests from forks with a branch of the same name
  (seen on `cli/cli`: `isCrossRepository: true`), and anyone can open one, since run branch
  names are public. The owner-qualified REST filter returns only this repository's branch.
  Without the owner, GitHub ignores the filter. `gh pr view <branch>`, which `fidfab-pr-status`
  uses, already skips fork pull requests. The stage needs exactly one open pull request. With
  none it has nothing to tidy; with two, the base is ambiguous.
- Rebase target: the merge base with that pull request's base branch, not the tip of the base
  branch as in the prompt the task quotes. The tree then stays the one that was reviewed and
  tested, which makes `git diff --quiet <before> HEAD` a complete check that the rewrite
  changed history only. Conflicts with a moved base remain the steward's job.
- Push: `--force-with-lease="<branch>:<remote>"` names the commit the agent examined. A bare
  `--force-with-lease` after `git fetch` leases against the ref just fetched and would
  overwrite commits someone pushed in between.
- A resumed or retried attempt finds the rewrite already on GitHub and the local branch reset
  to the old checkpoint. Identical trees tell that case from someone else's push; the prompt
  then adopts the remote history, so later checkpoint pushes fast-forward again.
- Apart from the gate on `context.pr_status`, which the graph enforces, these guarantees are
  instructions to the agent, as with the steward's own rebase; no script enforces them.
- The prompt reads no workflow input, so the component can be imported without defining one.

## Verification notes

- Not run: the stage itself in a live Fabro run (needs Docker and credentials, and it pushes to
  GitHub). If Fabro's push after the stage were not a fast-forward, the code on GitHub would
  still be the reviewed tree. The run would end as `publish_failed`, or the branch would get its
  checkpoint history back. Worth one run on a throwaway pull request before relying on it.
  The commands of the prompt were exercised by hand in a scratch repository with a bare
  remote: the normal rewrite, a resumed attempt, a concurrent push (rejected by the lease,
  caught by the checks after a fetch) and a base branch that moved.
- The run's GitHub token has no workflow scope, so a commit that touches
  `.github/workflows/` cannot be pushed (see pull request #15). `tests/test-logical-commits.sh`
  runs in CI through `tests/validate-workflows.sh` instead of a new step in `ci.yml`.
- `scripts/render-graphs.sh` works in the sandbox without a LiteLLM proxy: `fabro install
  --non-interactive --skip-llm --github-strategy token --github-username <login>`, append the
  `[llm.providers.litellm]` block from `scripts/setup.sh` to `~/.fabro/settings.toml`, set any
  value for the `LITELLM_API_KEY` secret, `fabro server restart`.
