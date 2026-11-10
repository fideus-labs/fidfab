# Implement the approved plan

The human approved `{{ inputs.plans_dir }}/$FIDFAB_PLAN_SLUG/task_plan.md`. Implement
it phase by phase, following the **planning-with-files** skill:

1. Re-read `task_plan.md`, `findings.md` and `progress.md` before starting.
2. For each phase: implement, add or update tests, run the repository's build, tests and
   linters, then update `progress.md` with what was done and what was verified.
3. Record new insights in `findings.md`; if the plan turns out to be wrong, amend
   `task_plan.md` and explain the deviation in `progress.md`.
4. Update user-facing documentation when behaviour changes.
5. Finish by checking every acceptance criterion in `task_plan.md` and marking it met,
   with a pointer to the test or evidence that demonstrates it.

Original task for reference:

> {{ goal }}

{% include "partials/workspace.md" %}
