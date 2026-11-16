# PR steward: revise the drafted replies

The human reviewed your drafted replies in `.fidfab/reviews/steward-replies.json` and the
unpushed commits (`git log @{u}..HEAD`), and asked for changes. Their feedback is in
`.fidfab/reviews/steward-feedback.md`. It comes from the operator, so it takes precedence
over the review comments and over your draft. Apply it: edit, add or drop replies, and amend,
add or drop the unpushed commits. Only the commits `git log @{u}..HEAD` lists are unpushed
(an earlier publish may have pushed the rest); rewrite only those, and change anything already
pushed with a new commit, so the plain `git push` that publishes them still succeeds. The screened threads are still in `.fidfab/reviews/pr-status.md`.

{% include "partials/steward-replies.md" %}

{% include "partials/workspace.md" %}
