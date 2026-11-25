# CodeRabbit review and autonomous fix

Use the **code-review** skill (CodeRabbit CLI) and follow its section
"4. Fix Issues (Autonomous Workflow)". The previous stage ran CodeRabbit on this branch
and saved its complete review to `.fidfab/reviews/coderabbit.md`, so start from the findings:

1. Read the findings in `.fidfab/reviews/coderabbit.md` and create a task list from them.
2. Fix the actionable issues within the scope of this branch, prioritising critical and
   major findings. Verify each fix with the repository's tests and linters.
3. Re-run `fidfab-coderabbit review` to confirm the fixes (it rewrites `coderabbit.md` with
   the new review; your task list keeps the first).
   Repeat at most twice more.
4. Write `.fidfab/reviews/coderabbit-response.md` recording, per finding of the first
   review: severity, decision (fixed / fixed-differently / not-an-issue / deferred) and
   the evidence.

The Codex and Claude reviews, in a workflow that runs them, have already been addressed
(`.fidfab/reviews/codex-review-response.md`, `.fidfab/reviews/claude-review-response.md`);
note when a finding duplicates one already handled.

If a confirming re-run fails (a usage limit or a login error), say at the top of
`.fidfab/reviews/coderabbit-response.md` that the fixes were not confirmed by CodeRabbit,
and finish; do not invent findings.

{% include "partials/workspace.md" %}
