# Progress Log

## Phases

| Phase | Status |
|-------|--------|
| 1. Fix the helper (`fidfab-coderabbit`) | pending |
| 2. Bootstrap reports the reason | pending |
| 3. Prompts fall back instead of stopping | pending |
| 4. Tests | pending |
| 5. Docs and verification | pending |

## Session: 2026-11-17 (planning)

- Read the helper, bootstrap, the `coderabbit-review` component, both prompts, the tests,
  CI and the README sections.
- Reproduced the failure against the real CLI: login rejects the vault key as a user API
  key; `auth status --agent` exits 0 with `"authenticated":false`; the helper's grep
  reports it as available.
- Checked the CodeRabbit headless and agent-mode docs and the code-review skill.
- Wrote `task_plan.md` and `findings.md`. No code changed.

## Test results

| Test | Result |
|------|--------|
| (none run yet; planning only) | |

## Errors

| Error | Resolution |
|-------|------------|
| `fabro` not installed in the sandbox | `tests/validate-workflows.sh` cannot run here; plan makes no graph changes |
