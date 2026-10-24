# Revise the plan

The human reviewer has read `{{ inputs.plans_dir }}/{{ inputs.plan_slug }}/task_plan.md`
and asked for changes. Their feedback is in the preamble above under `human.gate.text`.

Update `task_plan.md` (and `findings.md` if new research was needed) to address every
point of feedback. Where you disagree, say so explicitly in an "Open questions" section
rather than silently ignoring the feedback. Keep the plan's acceptance criteria
observable and testable.

End your reply by printing the full contents of the revised `task_plan.md` inside a
fenced markdown block.

{% include "partials/workspace.md" %}
