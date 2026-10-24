{% include "partials/review-priorities.md" %}

## Scope and output

- The diff to review is the output of `fidfab-diff` (merge base of this branch with the
  base branch → working tree). Read the surrounding code as needed for context, but only
  comment on changed lines.
- Use Serena for symbol-level navigation.
- This is an independent second review: do **not** read `.fidfab/reviews/codex-review.md`
  or the other review files before you have written your own findings.
- Write the findings list to `.fidfab/reviews/claude-review.md`. Start the file with one
  line stating the number of findings per severity. If there are no findings, write
  `No findings.` and explain briefly what you checked.
- Do not modify any other file.
