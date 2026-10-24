# PR steward iteration

Use the `gh` CLI to bring the open pull request for this branch to a mergeable state. The
current status summary from `fidfab-pr-status` is in the preamble.

1. **Review comments.** List review threads and comments:
   `gh pr view --comments`, and for inline threads use `gh api graphql` on
   `pullRequest.reviewThreads` (include `isResolved`, `path`, `line`, comment bodies and
   `id`). For each unresolved thread: verify the point against the code, address it when
   appropriate (code and tests), and reply with a follow-up comment describing the
   approach taken (or the evidence for not changing anything). Then mark the thread
   resolved with the GraphQL mutation `resolveReviewThread(input:{threadId:...})` via
   `gh api graphql`. Do not resolve threads you did not actually address.
2. **Merge conflicts.** If `mergeable` is `CONFLICTING`, `git fetch origin` and
   `git rebase origin/$FIDFAB_BASE_BRANCH`, resolve conflicts carefully (keep both the
   upstream intent and this branch's intent, re-run tests), then
   `git push --force-with-lease`.
3. **CI.** Check `gh pr checks` (and `gh run view --log-failed` for failures). Fix failing
   tests or lints at their root cause, never by deleting or weakening tests, and push.
   Note that CI may still be pending; do not wait for it here — the workflow waits.
4. Commit each fix with a clear message and push (`git push`, or `--force-with-lease`
   only after a rebase).
5. Summarise what you did in `.fidfab/reviews/steward-log.md` (append a dated entry).

If nothing needs attention, say so and make no changes.

{% include "partials/workspace.md" %}
