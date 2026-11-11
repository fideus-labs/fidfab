# Plan (medium implementation)

Create an implementation plan for this task using the **planning-with-files** skill:

> {{ goal }}

Write the artifacts to `{{ inputs.plans_dir }}/$FIDFAB_PLAN_SLUG/`:

- `task_plan.md` — goal, context, numbered phases with concrete steps, risks and open
  questions, and explicit **acceptance criteria** (observable, testable statements).
- `findings.md` — what you learned about the code base while planning: relevant modules,
  existing tests, conventions, prior art, external references.
- `progress.md` — initialised with the phase list; later stages update it.

Research before you plan: use Serena to map the relevant code, read tests and docs, and
consult the web when the task touches external specifications or libraries. Prefer
understanding over speed. Do not implement anything yet.

Size the plan so that a single focused session can implement it. If the task is really
larger than that, say so in `task_plan.md` and propose how to split it.

End your reply by printing the full contents of `task_plan.md` inside a fenced markdown
block so the human reviewer can read it in the run transcript.

{% include "partials/workspace.md" %}
