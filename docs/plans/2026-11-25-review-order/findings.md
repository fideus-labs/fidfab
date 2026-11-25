# Findings

- The review order is one edge chain, identical in `small`, `medium` and `verify`:
  `coverage -> coderabbit -> codex -> claude -> security -> personal -> ship -> steward`.
  `large` imports no review component (it critiques the roadmap with its own Codex node).
- The components do not depend on each other through the graph: each is a self-contained
  subgraph, and no edge condition or `context_updates` key links the three reviews.
- Prompts that know about the order:
  - `review-claude.md` calls itself "an independent second review" and tells the agent not to
    read `codex-review.md` "or the other review files". Still true, and now literally: Claude is
    the second of the three.
  - `address-claude.md` says the Codex review has already been addressed. Still true.
  - `coderabbit-review-fix.md` and `claude-builtin-review.md` said nothing about other reviews,
    which was right while CodeRabbit ran first.
  - `pull-request.md` lists the review stages for the PR description in pipeline order.
- "The previous stage ran CodeRabbit" in `coderabbit-review-fix.md` means the `run` script node
  inside the component, not the stage before the component.
- No test pinned the order before this change: `fabro validate` accepts any order, and
  `tests/test-logical-commits.sh` only checks steward -> history.
- `tests/test-pipeline-order.sh` tells a stage by the component file its placeholder imports,
  and walks the graph from the coverage check along the only edge out of each stage. It reads
  line by line: an edge chain continued on the next line, a quoted node id, a `{group}`, a fork
  or a loop gives a `?` and fails, as do an edge from a node off the chain into a stage after
  the coverage check (it skips the stages before) and a stage imported a second time (the copy
  off the chain, say ahead of the coverage check, runs out of order; `fabro validate` accepts
  it). It tells stages only by the component they import, so an agent node outside the
  components that reviews ahead of them goes unnoticed.
- `awk` in the sandbox is mawk 1.3.4; no gawk to try the test on. The new scanner uses only
  constructs `tests/test-logical-commits.sh` already runs in CI.
- Checks ran on Fabro 0.423.0-nightly.0 (the installer gave 0.254.0, `fabro upgrade
  --prerelease` the nightly), installed as the rm-carbon findings describe.
- `scripts/render-graphs.sh` with the throwaway server from the rm-carbon findings still works
  on that version: `large.svg`, whose graph did not change, came out byte-identical. The server
  commands ran under `env -i` with a scratch `HOME`, `PATH` and a placeholder `GH_TOKEN`, so
  the server process held none of the sandbox's credentials. `fabro install` prints the dev
  token of the server it starts; it goes away with the scratch `HOME`.
