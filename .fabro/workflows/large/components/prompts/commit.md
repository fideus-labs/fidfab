# Commit the work

The branch has passed coverage, code, security and (where applicable) audit reviews.
Create a sensible, descriptive commit:

1. Run the repository's formatter and ensure the build and tests pass one final time.
2. Inspect `fidfab-diff --stat` and the planning and review artifacts in
   `{{ inputs.plans_dir }}` and `.fidfab/reviews/` to understand what changed and why.
3. Stage all intended changes (`git add -A`, excluding anything that should not be
   committed, such as build outputs or secrets; `.fidfab/` is already excluded).
4. Write a commit message following the repository's convention (Conventional Commits if
   the history uses them): a concise imperative subject line (≤ 72 characters), a blank
   line, and a body that explains **what** changed and **why**, referencing the task:

   > {{ goal }}

   Mention notable implementation details and anything reviewers should know. If several
   logically separate changes exist, make several commits.
5. Run `git log --oneline -5` and `git status` and report the result.

Do not push; the next stage pushes and opens the pull request.

{% include "partials/workspace.md" %}
