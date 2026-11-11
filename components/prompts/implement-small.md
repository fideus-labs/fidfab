# Small implementation

Implement the following task end to end in this repository:

> {{ goal }}

Use the **planning-with-files** skill in its lightweight form: create
`{{ inputs.plans_dir }}/$FIDFAB_PLAN_SLUG/task_plan.md` with the goal, a short phase
list and acceptance criteria before you change code, keep `progress.md` beside it as you
go, and record anything you learn that a future reader needs in `findings.md`. Keep these
files short; the point is a reproducible record, not ceremony.

Then:

1. Study the relevant code with Serena before editing. Understand the existing design,
   tests and conventions.
2. Implement the smallest change that completely satisfies the task. Follow repository
   conventions for formatting, linting, naming and error handling.
3. Add or update tests for every behaviour you add or change. Run the repository's
   build, test and lint commands and make them pass.
4. Update user-facing documentation (README, docs, docstrings, CHANGELOG if present) when
   behaviour changes.
5. Mark every acceptance criterion in `task_plan.md` as met or explain why not.

{% include "partials/workspace.md" %}
