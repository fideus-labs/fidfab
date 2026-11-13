{% include "partials/review-priorities.md" %}

## Scope and output

- The diff to review is the output of `fidfab-diff` (merge base of this branch with the
  base branch → working tree). Read the surrounding code as needed for context, but only
  comment on changed lines.
- Use your shell and file tools for navigation (`fidfab-diff --names`, `rg`, `git log`,
  `git show`). Do not install tools or run builds that change the working tree.
- This is an independent review: do **not** read the other files in `.fidfab/reviews/`
  before you have written your own findings. The Codex review has already been
  addressed, so its fixes are part of the diff you see.
- Write the findings list to `.fidfab/reviews/carbon-review.md`. Start the file with one
  line stating the number of findings per severity. If there are no findings, write
  `No findings.` and explain briefly what you checked.
- Do not modify any other file.
