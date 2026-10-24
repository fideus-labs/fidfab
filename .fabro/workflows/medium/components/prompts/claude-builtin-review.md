# Code review (CodeRabbit unavailable — Claude built-in review)

CodeRabbit was unavailable after a retry. Perform the review yourself with Claude Code's
built-in code review capability (the `/code-review` command from the official plugin
when available, otherwise `/review`; if neither is available in this session, perform an
equivalent systematic review of the diff).

1. Review the complete branch diff (`fidfab-diff`). Focus on correctness, security,
   compatibility, performance and tests; report only on changed lines.
2. Save the findings to `.fidfab/reviews/coderabbit.md` with a first line stating
   `CodeRabbit unavailable; review produced by Claude Code built-in review`.
3. Fix the actionable issues, prioritising critical and major findings, and verify each
   fix with the repository's tests and linters.
4. Write `.fidfab/reviews/coderabbit-response.md` recording, per finding: severity,
   decision (fixed / fixed-differently / not-an-issue / deferred) and the evidence.

{% include "partials/workspace.md" %}
