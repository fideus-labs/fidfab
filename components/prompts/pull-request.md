# Open and refine the pull request

1. Push the current branch: `git push -u origin HEAD`.
2. Create the pull request with `gh pr create --fill --base "$FIDFAB_BASE_BRANCH"`
   (add `--draft` if `{{ inputs.draft_pr }}` is `true`).
3. Analyse the changes in this branch (`git log origin/$FIDFAB_BASE_BRANCH..HEAD`,
   `fidfab-diff --stat`, the planning artifacts under `{{ inputs.plans_dir }}` and the
   review records under `.fidfab/reviews/`) and write the title and description below.
   fidfab's workflows review one version. A workflow that reviews several moves each earlier
   version's records to `.fidfab/reviews-<n>/` before reviewing the next (FidLab's research does,
   with `fidlab.py base scored`): read every such folder too, so that a review skipped for an
   earlier version still reaches the description.
   - a concise, descriptive **title** that summarises the change;
   - a **description** with sections: *What changed*, *Why* (based on the task context:
     "{{ goal }}"), *Implementation notes* (important details, trade-offs, follow-ups),
     *Verification* (tests added, review stages that ran: coverage, CodeRabbit or built-in
     review, Codex review, Claude review, security review, and the personal-data
     decision with the audit result when it ran). A review record that says the review
     was skipped, or that Claude's built-in review stood in for CodeRabbit, goes first in
     *Verification*, in bold.
4. Update the PR with `gh pr edit <number> --title ... --body-file <file>`.
5. Post the review records as one PR comment so reviewers can see how each finding was
   handled: concatenate the `*-response.md` files from any `.fidfab/reviews-<n>/` in order, then
   `.fidfab/reviews/`, each under the name of its folder (abbreviate if
   longer than ~400 lines) and `gh pr comment <number> --body-file <file>`.
6. Print the PR URL on the last line of your reply.

{% include "partials/workspace.md" %}
