{% include "partials/review-priorities.md" %}

## Scope and output

- The diff to review is the output of `fidfab-diff` (merge base of this branch with the
  base branch → working tree). Read the surrounding code as needed for context, but only
  comment on changed lines.
- Use the cocoindex-code index (`ccc`) for fast semantic search of the code base.
- Write the findings list to `.fidfab/reviews/codex-review.md`. Start the file with one
  line stating the number of findings per severity. If there are no findings, write
  `No findings.` and explain briefly what you checked.
- Do not modify any other file.
