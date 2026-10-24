# Test coverage of changed behaviour

Review the branch diff (`fidfab-diff`) and determine whether every behaviour it adds or
changes is exercised by tests.

1. Map each changed function, branch, error path and public interface in the diff to the
   tests that cover it. Use the repository's coverage tooling if present (for example
   `cargo llvm-cov`, `pytest --cov`, `vp test --coverage`) to confirm rather than guess.
2. For uncovered behaviour, write focused tests that would fail without the change. Cover
   edge cases: empty inputs, boundaries, error handling, concurrency where relevant.
3. Run the full relevant test suite and make it pass.
4. Write `.fidfab/reviews/coverage.md` with a table: changed behaviour, covering test(s),
   status (covered / added / intentionally uncovered with reason).

Do not refactor unrelated code and do not commit.

{% include "partials/workspace.md" %}
