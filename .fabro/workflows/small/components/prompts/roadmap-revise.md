# Roadmap: revise with human feedback

The human reviewer has read the roadmap in `{{ inputs.plans_dir }}/$FIDFAB_PLAN_SLUG/`
and asked for changes. Their feedback is in the preamble above under `human.gate.text`.

Address every point: add, remove, split, merge or reorder work items; deepen research
where asked (update `research.md` with sources); sharpen implementation plans and
acceptance criteria. Keep each work item sized for one `fidfab medium` run. Where you
disagree, say so under "Open questions" in `README.md` instead of silently ignoring the
feedback.

End your reply by printing the full contents of the revised `README.md` inside a fenced
markdown block and a short changelog of what you changed in this iteration.

{% include "partials/workspace.md" %}
