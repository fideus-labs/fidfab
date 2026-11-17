# Progress: CodeRabbit stage

## Phases

| Phase | Status |
|-------|--------|
| 1. Host-side test for the wrapper (test first) | pending |
| 2. Fix `fidfab-coderabbit` | pending |
| 3. Bootstrap and setup report the real reason | pending |
| 4. Prompts fall back instead of stopping | pending |
| 5. In-image test and documentation | pending |
| 6. Verification | pending |

## Log

### 2026-11-17 planning

- Reproduced the failure in the sandbox with CodeRabbit CLI 0.9.5: the key in
  `CODERABBIT_API_KEY` is a user API key and is rejected at login; `fidfab-coderabbit
  available` still exits 0 because its `grep` matches `not_authenticated`.
- Read the wrapper, bootstrap, the component graph, both prompts, the tests and CI; read the
  CodeRabbit headless documentation and the installed code-review skill.
- Wrote `task_plan.md` and `findings.md`. No code changed.
- Not run: `tests/validate-workflows.sh` and `tests/test-image.sh` (no `fabro`, no Docker
  daemon in the sandbox).

## Test results

None yet.
