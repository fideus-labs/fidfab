# CodeRabbit review and autonomous fix

Use the **code-review** skill (CodeRabbit CLI) and follow its section
"4. Fix Issues (Autonomous Workflow)". The implementation is already in the working
tree, so start at the review step:

1. Run `fidfab-coderabbit review` (this calls `coderabbit review --agent` against the base
   branch) and save the raw output to `.fidfab/reviews/coderabbit.md`.
2. Create a task list from the findings.
3. Fix the actionable issues within the scope of this branch, prioritising critical and
   major findings. Verify each fix with the repository's tests and linters.
4. Re-run the review to confirm the fixes. Repeat at most twice more.
5. Write `.fidfab/reviews/coderabbit-response.md` recording, per finding: severity,
   decision (fixed / fixed-differently / not-an-issue / deferred) and the evidence.

If the CodeRabbit CLI reports a rate limit or authentication failure, say so clearly at
the top of `.fidfab/reviews/coderabbit-response.md` and finish; do not invent findings.

{% include "partials/workspace.md" %}
