# Task plan: agent effort levels

## Goal

Set the Claude implementation effort level to `xhigh`, the Claude and Codex review effort
levels to `high`, every other Claude and Codex effort level to `medium`, and the Gemini
effort levels to `medium`.

## Current Phase

All phases complete

## Next Step

None; hand over to verification.

## Phases

### Phase 1: Survey
**Status:** complete

Find every place an effort level is set or defaulted (ACP wrappers, `.fabro` nodes,
`workflow.toml`, Codex config) and how Fabro sets effort on native (Gemini) nodes.

### Phase 2: Implement
**Status:** complete

Set an explicit effort on every agent node, sync the vendored components, add a test that
pins the policy, update the README.

### Phase 3: Verify
**Status:** complete

Run the repository checks listed in AGENTS.md.

## Acceptance criteria

- [x] Claude implementation nodes (`small`, `medium`: `implement`) run with `--effort xhigh`.
- [x] Claude and Codex review nodes run with `--effort high`.
- [x] Every other Claude and Codex node runs with `--effort medium`; the baked Codex default is `medium`.
- [x] Gemini nodes request `reasoning_effort` `medium` (Carbon review nodes and the `[run.model]` default).
- [x] No agent node is left without an explicit effort; a test enforces the table.
- [x] `scripts/sync-components.sh --check`, `shellcheck -S warning`, and the new test pass; `tests/validate-workflows.sh` passes where `fabro` is available.
- [x] README documents the effort policy.

## Errors Encountered

| Error | Attempt | Resolution |
|-------|---------|------------|
| Negative test used `git checkout` to undo a deliberate break, which also dropped the uncommitted `--effort medium` on `components/coverage.fabro` | 1 | Re-applied the edit and re-synced; `tests/test-effort-levels.sh` would have caught it |

## Notes on the acceptance criteria

All met. `fabro validate` was run with Fabro 0.415.0-nightly.0 installed into `~/.fabro` of the
sandbox (the image does not ship it). Not verified here: a live Gemini call, so that the proxy
and Vertex AI honour `reasoning_effort`; see `findings.md`.
